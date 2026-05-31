import UIKit

final class OCRService {
    private let serverURL: String

    init(serverURL: String) {
        self.serverURL = serverURL
    }

    func analyze(image: UIImage, mode: CameraManager.ProcessingMode, completion: @escaping (AnalysisResponse) -> Void) {
        guard let url = URL(string: serverURL) else {
            completion(
                AnalysisResponse(
                    status: "error",
                    mode: mode.rawValue,
                    detectedText: nil,
                    voiceGuide: "분석을 시작하려면 앱 설정에 백엔드 서버 주소를 입력해 주세요.",
                    warnings: nil,
                    detections: nil
                )
            )
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            completion(
                AnalysisResponse(
                    status: "error",
                    mode: mode.rawValue,
                    detectedText: nil,
                    voiceGuide: "카메라 이미지를 업로드할 수 있도록 준비하지 못했습니다.",
                    warnings: nil,
                    detections: nil
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
                        voiceGuide: "서버 연결에 실패했습니다: \(error.localizedDescription)",
                        warnings: nil,
                        detections: nil
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
                        voiceGuide: "서버 응답을 읽을 수 없습니다.",
                        warnings: nil,
                        detections: nil
                    )
                )
                return
            }

            completion(response)
        }.resume()
    }
}
