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
    let warnings: [String]?
    let detections: [DetectionResponse]?

    enum CodingKeys: String, CodingKey {
        case status
        case mode
        case detectedText = "detected_text"
        case voiceGuide = "voice_guide"
        case warnings
        case detections
    }
}

struct DetectionResponse: Decodable, Sendable {
    let label: String
    let koreanLabel: String?
    let confidence: Double?
    let position: String?
    let bboxXYXY: [Double]?
    let areaRatio: Double?
    let approaching: Bool?
    let riskScore: Int?

    enum CodingKeys: String, CodingKey {
        case label
        case koreanLabel = "korean_label"
        case confidence
        case position
        case bboxXYXY = "bbox_xyxy"
        case areaRatio = "area_ratio"
        case approaching
        case riskScore = "risk_score"
    }
}
