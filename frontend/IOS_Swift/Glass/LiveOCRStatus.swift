import SwiftUI

enum LiveOCRStatus: String {
    case searching = "Searching for text..."
    case detected = "Text detected"
    case stabilizing = "Stabilizing..."
    case reading = "Reading text..."
    case coolingDown = "Listening for new text..."
    case unavailable = "Camera unavailable"

    var accessibilityLabel: String {
        rawValue
    }
}

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
