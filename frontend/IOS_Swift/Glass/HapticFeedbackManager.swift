import UIKit

enum HapticEvent {
    case readableTextConfirmed
    case ocrFailed
}

enum OCRHapticPulseState {
    case searching
    case candidate
}

struct OCRHapticConfiguration {
    let searchingInterval: TimeInterval
    let candidateInterval: TimeInterval
    let timeoutInterval: TimeInterval
    let timeoutIntervalAfterNoText: TimeInterval

    static let standard = OCRHapticConfiguration(
        searchingInterval: 1.8,
        candidateInterval: 1.0,
        timeoutInterval: 12.0,
        timeoutIntervalAfterNoText: 4.0
    )
}

final class HapticFeedbackManager: NSObject {
    private let configuration: OCRHapticConfiguration
    private var pulseTimer: Timer?
    private var pulseState: OCRHapticPulseState?
    private var pulseStartedAt: Date?

    init(configuration: OCRHapticConfiguration = .standard) {
        self.configuration = configuration
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stopRepeatingPulses),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pulseTimer?.invalidate()
    }

    func updateOCRPulseState(_ state: OCRHapticPulseState) {
        DispatchQueue.main.async {
            guard self.pulseState != state else { return }

            self.pulseState = state
            self.pulseStartedAt = Date()
            self.scheduleNextPulse(after: self.interval(for: state))
        }
    }

    @objc func stopRepeatingPulses() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.stopRepeatingPulses()
            }
            return
        }

        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseState = nil
        pulseStartedAt = nil
    }

    func play(_ event: HapticEvent) {
        DispatchQueue.main.async {
            switch event {
            case .readableTextConfirmed:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)
            case .ocrFailed:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func scheduleNextPulse(after interval: TimeInterval) {
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.emitPulseAndReschedule()
        }
    }

    private func emitPulseAndReschedule() {
        guard let pulseState else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.42)
        scheduleNextPulse(after: interval(for: pulseState))
    }

    private func interval(for state: OCRHapticPulseState) -> TimeInterval {
        if let pulseStartedAt,
           Date().timeIntervalSince(pulseStartedAt) >= configuration.timeoutInterval {
            return configuration.timeoutIntervalAfterNoText
        }

        switch state {
        case .searching:
            return configuration.searchingInterval
        case .candidate:
            return configuration.candidateInterval
        }
    }
}
