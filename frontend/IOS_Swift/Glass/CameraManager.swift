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
    struct AnalysisResponse: Decodable, Sendable {
        let status: String
        let mode: String
        let detectedText: String?
        let voiceGuide: String
        
        enum CodingKeys: String, CodingKey {
            case status
            case mode
            case detectedText = "detected_text"
            case voiceGuide = "voice_guide"
        }
    }
    
    enum ProcessingMode: String {
        case liveAnalyzing = "live"
        case textDescription = "text"
    }
    
    @Published var session = AVCaptureSession()
    @Published var latestGuide = "Live Analyzing mode is ready."
    @Published var latestDetectedText: String?
    @Published var isProcessing = false
    
    private let output = AVCaptureVideoDataOutput()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let processingQueue = DispatchQueue(label: "glass.processing.queue")
    private var latestFrame: UIImage?
    private var currentMode: ProcessingMode = .liveAnalyzing
    private var lastLiveRequestDate: Date = .distantPast
    private let liveRequestInterval: TimeInterval = 2.0
    private var serverURL = "http://100.64.174.44:8000/analyze"
    
    override init() {
        super.init()
        checkPermissions()
        setupSession()
    }
    
    func setMode(_ mode: ProcessingMode) {
        currentMode = mode
        
        let message: String
        switch mode {
        case .liveAnalyzing:
            latestDetectedText = nil
            message = "Live Analyzing mode is on. The app will keep checking the scene ahead."
        case .textDescription:
            message = "Text Description mode is on. Tap the read text button to scan nearby text."
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
        
        processImage(frame, mode: .textDescription)
    }
    
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        default:
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
        guard let image = imageFromSampleBuffer(sampleBuffer) else { return }
        latestFrame = image
        
        guard currentMode == .liveAnalyzing else { return }
        guard !isProcessing else { return }
        guard Date().timeIntervalSince(lastLiveRequestDate) >= liveRequestInterval else { return }
        
        lastLiveRequestDate = Date()
        processImage(image, mode: .liveAnalyzing)
    }
    
    private func imageFromSampleBuffer(_ buffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }
    
    private func processImage(_ image: UIImage, mode: ProcessingMode) {
        guard !isProcessing else { return }
        
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        sendImageToServer(image: image, mode: mode) { [weak self] response in
            guard let self else { return }
            self.updateResponse(response, shouldSpeak: true)
            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }
    }
    
    private func sendImageToServer(image: UIImage, mode: ProcessingMode, completion: @escaping (AnalysisResponse) -> Void) {
        guard let url = URL(string: serverURL) else {
            DispatchQueue.main.async {
                self.isProcessing = false
            }
            completion(
                AnalysisResponse(
                    status: "error",
                    mode: mode.rawValue,
                    detectedText: nil,
                    voiceGuide: "Set the backend server IP address in CameraManager to start analysis."
                )
            )
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            DispatchQueue.main.async {
                self.isProcessing = false
            }
            completion(
                AnalysisResponse(
                    status: "error",
                    mode: mode.rawValue,
                    detectedText: nil,
                    voiceGuide: "The camera image could not be prepared for upload."
                )
            )
            return
        }
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"mode\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(mode.rawValue)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"frame.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(
                    AnalysisResponse(
                        status: "error",
                        mode: mode.rawValue,
                        detectedText: nil,
                        voiceGuide: "Server connection failed: \(error.localizedDescription)"
                    )
                )
                return
            }
            
            guard let data,
                  let response = try? JSONDecoder().decode(AnalysisResponse.self, from: data) else {
                completion(
                    AnalysisResponse(
                        status: "error",
                        mode: mode.rawValue,
                        detectedText: nil,
                        voiceGuide: "The server returned an unreadable response."
                    )
                )
                return
            }
            
            completion(response)
        }.resume()
    }
    
    private func updateResponse(_ response: AnalysisResponse, shouldSpeak: Bool) {
        DispatchQueue.main.async {
            self.latestGuide = response.voiceGuide
            self.latestDetectedText = response.detectedText
        }
        
        guard shouldSpeak else { return }
        speak(response.voiceGuide)
    }
    
    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        
        processingQueue.async {
            self.speechSynthesizer.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = 0.48
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            self.speechSynthesizer.speak(utterance)
        }
    }
}
