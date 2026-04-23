//
//  CameraManager.swift
//  Glass
//
//  Created by JoMinHui on 4/10/26.
//

import AVFoundation
import UIKit
import Combine

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var session = AVCaptureSession()
    @Published var lastResponse: String = "대기 중..." // 👈 서버 응답 저장용
    var lastCapturedImage: UIImage? // 👈 전송할 마지막 프레임 저장
        
    private let output = AVCaptureVideoDataOutput()
    var onFrameCaptured: ((UIImage) -> Void)?
    
    override init() {
        super.init()
        checkPermissions()
        setupSession()
    }

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        default: break
        }
    }

    func setupSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    // 카메라 프레임이 들어올 때마다 호출되는 함수
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let image = imageFromSampleBuffer(sampleBuffer) else { return }
        DispatchQueue.main.async {
            self.lastCapturedImage = image
            self.onFrameCaptured?(image)
        }
    }

    // 🚀 서버로 이미지를 업로드하는 핵심 함수
        func uploadImage(mode: String) {
            guard let image = lastCapturedImage else { return }
            // 1. 민희님 맥북의 IP 주소로 수정하세요!
            guard let url = URL(string: "http://192.168.XX.XX:8000/analyze") else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", for: HTTPHeaderField: "Content-Type")
            
            guard let imageData = image.jpegData(compressionQuality: 0.5) else { return }
            
            var body = Data()
            // 모드 데이터 추가
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"mode\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(mode)\r\n".data(using: .utf8)!)
            
            // 이미지 데이터 추가
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"frame.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            
            request.httpBody = body
            
            URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
                if let data = data,
                   let response = try? JSONDecoder().decode([String: String].self, from: data) {
                    DispatchQueue.main.async {
                        // 서버 응답(voice_guide)을 변수에 저장 -> UI가 자동으로 바뀜!
                        self?.lastResponse = response["voice_guide"] ?? "결과 없음"
                    }
                }
            }.resume()
        }
    private func imageFromSampleBuffer(_ buffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }
    
}
