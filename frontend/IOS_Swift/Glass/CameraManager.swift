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
    private let output = AVCaptureVideoDataOutput()
    
    // 이 클로저를 통해 메인 화면으로 프레임을 넘겨줄 겁니다.
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
        onFrameCaptured?(image)
    }

    private func imageFromSampleBuffer(_ buffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }
    
    func sendImageToServer(image: UIImage, mode: String, completion: @escaping (String) -> Void) {
        // 1. 민희님 맥북의 IP 주소로 수정하세요! (터미널에서 ifconfig 입력)
        guard let url = URL(string: "http://192.168.0.XX:8000/analyze") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", for: HTTPHeaderField: "Content-Type")
        
        // 2. 이미지를 JPEG 데이터로 변환
        guard let imageData = image.jpegData(compressionQuality: 0.5) else { return }
        
        var body = Data()
        // 모드 데이터 추가 (detection/text)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"mode\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(mode)\r\n".data(using: .utf8)!)
        
        // 이미지 데이터 추가
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"frame.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // 3. 서버로 전송
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data, let responseString = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // 서버가 보낸 "voice_guide" 텍스트 추출
                let guide = responseString["voice_guide"] as? String ?? ""
                DispatchQueue.main.async {
                    completion(guide)
                }
            }
        }.resume()
    }
}
