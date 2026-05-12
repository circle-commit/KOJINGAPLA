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
    @Published var latestGuide = "Live Analyzing mode is ready."
    @Published var latestDetectedText: String?
    @Published var textCaptureImage: UIImage?
    @Published var isProcessing = false
    @Published var liveOCRStatus: LiveOCRStatus = .searching

    private let output = AVCaptureVideoDataOutput()
    private let imageContext = CIContext()
    private let frameAnalyzer = OCRFrameAnalyzer()
    private let stabilityTracker = TextStabilityTracker()
    private let duplicateSuppressor = DuplicateTextSuppressor()
    private let speechManager = SpeechManager()
    private let hapticManager = HapticFeedbackManager()
    private var latestFrame: UIImage?
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
        switch mode {
        case .liveAnalyzing:
            latestDetectedText = nil
            textCaptureImage = nil
            liveOCRStatus = .searching
            message = "Live guidance active"
        case .textDescription:
            latestDetectedText = nil
            textCaptureImage = nil
            liveOCRStatus = .searching
            message = "OCR mode active. Point the camera at nearby text."
        }

        updateResponse(
            AnalysisResponse(
                status: "ready",
                mode: mode.rawValue,
                detectedText: nil,
                voiceGuide: message
            ),
            shouldSpeak: true
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
                    voiceGuide: "Camera permission is needed to use this app."
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
            lastLiveRequestDate = Date()
            processImage(image, mode: .liveAnalyzing, allowDuplicateSpeech: true)

        case .textDescription:
            analyzeTextFrame(sampleBuffer)
        }
    }

    private func analyzeTextFrame(_ sampleBuffer: CMSampleBuffer) {
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
            guard let image = self.imageFromSampleBuffer(sampleBuffer) else { return }

            self.latestFrame = image
            self.lastFullOCRRequestDate = Date()
            self.hapticManager.play(.readableTextDetected)
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
                    voiceGuide: "Camera frame is not ready yet. Please try again."
                ),
                shouldSpeak: true
            )
            return
        }

        latestDetectedText = nil
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
                self.hapticManager.play(.speechStarting)
            }

            self.updateResponse(response, shouldSpeak: shouldSpeak)

            DispatchQueue.main.async {
                self.isProcessing = false
                if mode == .textDescription {
                    self.liveOCRStatus = response.status == "error" ? .searching : .coolingDown
                    if response.status == "error" {
                        self.hapticManager.play(.ocrFailed)
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
        }

        guard shouldSpeak else { return }
        speechManager.speak(response.voiceGuide)
    }

    private func updateLiveOCRStatus(_ status: LiveOCRStatus) {
        DispatchQueue.main.async {
            guard self.currentMode == .textDescription else { return }

            if self.liveOCRStatus != status {
                self.liveOCRStatus = status
            }

            if self.latestDetectedText == nil || self.latestDetectedText?.isEmpty == true {
                self.latestGuide = status.rawValue
            }
        }
    }
}
