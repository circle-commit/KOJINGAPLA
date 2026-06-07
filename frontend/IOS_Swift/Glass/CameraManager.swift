//
//  CameraManager.swift
//  Glass
//
//  Created by JoMinHui on 4/10/26.
//

import AVFoundation
import Combine
import UIKit

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum ProcessingMode: String {
        case liveAnalyzing = "live"
        case textDescription = "text"
    }

    @Published var session = AVCaptureSession()
    @Published var latestGuide = "실시간 안내 모드가 준비되었습니다."
    @Published var latestDetectedText: String?
    @Published var textCaptureImage: UIImage?
    @Published var isProcessing = false
    @Published var liveOCRStatus: LiveOCRStatus = .searching
    @Published var latestLiveDirection = "center"
    @Published var latestLiveRiskScore = 0
    @Published var liveBoxes: [LiveGuidanceBox] = []
    @Published var liveImageSize: CGSize = .zero

    /// Only the most important detections are visualized; anything below this risk
    /// score is treated as "calm" and never drawn so the preview stays uncluttered.
    private static let liveBoxMinRisk = 55
    /// At most this many bounding boxes are shown at once (the highest-risk objects).
    private static let liveBoxMaxCount = 2

    private let output = AVCaptureVideoDataOutput()
    private let imageContext = CIContext()
    private let frameAnalyzer = OCRFrameAnalyzer()
    private let stabilityTracker = TextStabilityTracker()
    private let duplicateSuppressor = DuplicateTextSuppressor()
    private let speechManager = SpeechManager()
    private let hapticManager = HapticFeedbackManager()
    private var latestFrame: UIImage?
    private var latestFrameSize: CGSize = .zero
    private var currentMode: ProcessingMode = .liveAnalyzing
    private var lastLiveRequestDate: Date = .distantPast
    private var lastFullOCRRequestDate: Date = .distantPast
    private let liveRequestInterval: TimeInterval = 2.0
    private let fullOCRCooldown: TimeInterval = 3.0
    private let serverURL = "http://100.64.174.44:8000/analyze"
    private lazy var ocrService = OCRService(serverURL: serverURL)

    override init() {
        super.init()
        checkPermissions()
        setupSession()
    }

    func setMode(_ mode: ProcessingMode) {
        currentMode = mode
        stabilityTracker.reset()

        let message: String
        let shouldAnnounceMode: Bool
        switch mode {
        case .liveAnalyzing:
            latestDetectedText = nil
            textCaptureImage = nil
            liveOCRStatus = .searching
            latestLiveDirection = "center"
            latestLiveRiskScore = 0
            liveBoxes = []
            hapticManager.stopRepeatingPulses()
            message = "실시간 보행 안내를 시작합니다."
            shouldAnnounceMode = true
        case .textDescription:
            latestDetectedText = nil
            textCaptureImage = nil
            liveOCRStatus = .searching
            latestLiveDirection = "center"
            latestLiveRiskScore = 0
            liveBoxes = []
            hapticManager.updateOCRPulseState(.searching)
            message = "문자 읽기 모드입니다. 카메라를 가까운 문자에 맞춰주세요."
            shouldAnnounceMode = false
        }

        updateResponse(
            AnalysisResponse(
                status: "ready",
                mode: mode.rawValue,
                detectedText: nil,
                voiceGuide: message,
                warnings: nil,
                detections: nil
            ),
            shouldSpeak: shouldAnnounceMode
        )
    }

    func triggerTextCapture() {
        runFullTextOCRFromLatestFrame(allowDuplicateSpeech: true)
    }

    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        default:
            liveOCRStatus = .unavailable
            updateResponse(
                AnalysisResponse(
                    status: "error",
                    mode: currentMode.rawValue,
                    detectedText: nil,
                    voiceGuide: "이 앱을 사용하려면 카메라 권한이 필요합니다.",
                    warnings: nil,
                    detections: nil
                ),
                shouldSpeak: false
            )
        }
    }

    private func setupSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
        }

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        switch currentMode {
        case .liveAnalyzing:
            guard !isProcessing else { return }
            guard Date().timeIntervalSince(lastLiveRequestDate) >= liveRequestInterval else { return }
            guard let image = imageFromSampleBuffer(sampleBuffer) else { return }

            latestFrame = image
            latestFrameSize = image.size
            lastLiveRequestDate = Date()
            processImage(image, mode: .liveAnalyzing, allowDuplicateSpeech: true)

        case .textDescription:
            analyzeTextFrame(sampleBuffer)
        }
    }

    private func analyzeTextFrame(_ sampleBuffer: CMSampleBuffer) {
        let candidateFrame = imageFromSampleBuffer(sampleBuffer)
        if let candidateFrame {
            latestFrame = candidateFrame
        }

        frameAnalyzer.analyze(sampleBuffer: sampleBuffer) { [weak self] analysis in
            guard let self else { return }

            let decision = self.stabilityTracker.update(with: analysis)
            self.updateLiveOCRStatus(decision.status)

            guard decision.shouldRunFullOCR else { return }
            guard self.currentMode == .textDescription else { return }
            guard !self.isProcessing else { return }
            guard Date().timeIntervalSince(self.lastFullOCRRequestDate) >= self.fullOCRCooldown else {
                self.updateLiveOCRStatus(.coolingDown)
                return
            }
            guard let image = candidateFrame else { return }

            self.latestFrame = image
            self.lastFullOCRRequestDate = Date()
            self.hapticManager.stopRepeatingPulses()
            self.runFullTextOCRFromLatestFrame(allowDuplicateSpeech: false)
        }
    }

    private func runFullTextOCRFromLatestFrame(allowDuplicateSpeech: Bool) {
        guard currentMode == .textDescription else { return }
        guard let frame = latestFrame else {
            updateResponse(
                AnalysisResponse(
                    status: "error",
                    mode: currentMode.rawValue,
                    detectedText: nil,
                    voiceGuide: "카메라 화면이 아직 준비되지 않았습니다. 다시 시도해 주세요.",
                    warnings: nil,
                    detections: nil
                ),
                shouldSpeak: true
            )
            return
        }

        textCaptureImage = frame
        updateLiveOCRStatus(.reading)
        processImage(frame, mode: .textDescription, allowDuplicateSpeech: allowDuplicateSpeech)
    }

    private func imageFromSampleBuffer(_ buffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }

    private func processImage(_ image: UIImage, mode: ProcessingMode, allowDuplicateSpeech: Bool) {
        guard !isProcessing else { return }

        DispatchQueue.main.async {
            self.isProcessing = true
        }

        ocrService.analyze(image: image, mode: mode) { [weak self] response in
            guard let self else { return }
            guard self.currentMode == mode else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                return
            }
            let shouldSpeak = self.shouldSpeak(response: response, mode: mode, allowDuplicateSpeech: allowDuplicateSpeech)

            if shouldSpeak && mode == .textDescription {
                self.hapticManager.stopRepeatingPulses()
                self.hapticManager.play(.readableTextConfirmed)
            }

            self.updateResponse(response, shouldSpeak: shouldSpeak)

            DispatchQueue.main.async {
                self.isProcessing = false
                if mode == .textDescription {
                    self.liveOCRStatus = response.status == "error" ? .searching : .coolingDown
                    if response.status == "error" {
                        self.hapticManager.play(.ocrFailed)
                    } else if !shouldSpeak {
                        self.hapticManager.updateOCRPulseState(.searching)
                    }
                }
            }
        }
    }

    private func shouldSpeak(response: AnalysisResponse, mode: ProcessingMode, allowDuplicateSpeech: Bool) -> Bool {
        guard mode == .textDescription else { return true }
        guard response.status != "error" else { return true }
        guard let detectedText = response.detectedText, !detectedText.isEmpty else { return allowDuplicateSpeech }
        return allowDuplicateSpeech || duplicateSuppressor.shouldSpeak(detectedText)
    }

    private func updateResponse(_ response: AnalysisResponse, shouldSpeak: Bool) {
        DispatchQueue.main.async {
            self.latestGuide = response.voiceGuide
            self.latestDetectedText = response.detectedText
            self.updateLiveGuidanceState(from: response)
        }

        guard shouldSpeak else { return }
        hapticManager.stopRepeatingPulses()
        speechManager.speak(response.voiceGuide) { [weak self] in
            guard let self else { return }
            guard self.currentMode == .textDescription else { return }
            guard !self.isProcessing else { return }
            self.hapticManager.updateOCRPulseState(.searching)
        }
    }

    private func updateLiveGuidanceState(from response: AnalysisResponse) {
        guard response.mode == ProcessingMode.liveAnalyzing.rawValue else { return }
        guard response.status != "error",
              let detections = response.detections,
              let primaryDetection = detections.first else {
            latestLiveDirection = "center"
            latestLiveRiskScore = 0
            liveBoxes = []
            return
        }

        // Voice-guidance state is derived exactly as before — unchanged.
        latestLiveDirection = primaryDetection.position ?? "center"
        latestLiveRiskScore = primaryDetection.riskScore ?? 0

        // Visualization is additive: pick only the few highest-risk objects to draw.
        liveImageSize = latestFrameSize
        liveBoxes = makeLiveBoxes(from: detections, imageSize: latestFrameSize)
    }

    /// Builds bounding boxes for the highest-risk detections only.
    ///
    /// - Detections are sorted by `risk_score` (descending).
    /// - Nothing is drawn unless at least one object reaches `liveBoxMinRisk`, so a
    ///   calm scene keeps the camera preview clean.
    /// - At most `liveBoxMaxCount` boxes are returned (the top objects), each carrying
    ///   its own risk score so the UI can color it independently.
    private func makeLiveBoxes(from detections: [DetectionResponse], imageSize: CGSize) -> [LiveGuidanceBox] {
        guard imageSize.width > 0, imageSize.height > 0 else { return [] }

        let ranked = detections
            .filter { ($0.riskScore ?? 0) >= Self.liveBoxMinRisk && ($0.bboxXYXY?.count ?? 0) == 4 }
            .sorted { ($0.riskScore ?? 0) > ($1.riskScore ?? 0) }

        return ranked.prefix(Self.liveBoxMaxCount).compactMap { detection in
            guard let bbox = detection.bboxXYXY, bbox.count == 4 else { return nil }

            // Normalize pixel bbox (x1, y1, x2, y2) into the 0...1 image space.
            let x1 = min(bbox[0], bbox[2]) / imageSize.width
            let y1 = min(bbox[1], bbox[3]) / imageSize.height
            let x2 = max(bbox[0], bbox[2]) / imageSize.width
            let y2 = max(bbox[1], bbox[3]) / imageSize.height

            return LiveGuidanceBox(
                rect: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1),
                riskScore: detection.riskScore ?? 0,
                label: detection.koreanLabel ?? detection.label
            )
        }
    }

    private func updateLiveOCRStatus(_ status: LiveOCRStatus) {
        DispatchQueue.main.async {
            guard self.currentMode == .textDescription else { return }
            guard !self.isProcessing || status == .reading else { return }

            if self.liveOCRStatus != status {
                self.liveOCRStatus = status
            }

            if self.latestDetectedText == nil || self.latestDetectedText?.isEmpty == true {
                self.latestGuide = status.rawValue
            }

            switch status {
            case .searching, .coolingDown:
                if !self.isProcessing {
                    self.hapticManager.updateOCRPulseState(.searching)
                }
            case .detected:
                if !self.isProcessing {
                    self.hapticManager.updateOCRPulseState(.detected)
                }
            case .stabilizing:
                if !self.isProcessing {
                    self.hapticManager.updateOCRPulseState(.stabilizing)
                }
            case .reading, .unavailable:
                self.hapticManager.stopRepeatingPulses()
            }
        }
    }
}
