import UIKit

enum HapticEvent {
    case readableTextDetected
    case speechStarting
    case ocrFailed
}

final class HapticFeedbackManager {
    func play(_ event: HapticEvent) {
        DispatchQueue.main.async {
            switch event {
            case .readableTextDetected:
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
            case .speechStarting:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
            case .ocrFailed:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}
