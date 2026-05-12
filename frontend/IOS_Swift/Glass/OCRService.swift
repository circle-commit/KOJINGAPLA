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
}
