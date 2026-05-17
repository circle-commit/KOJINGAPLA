import AVFoundation

final class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, onFinish: (() -> Void)? = nil) {
        guard !text.isEmpty else { return }

        DispatchQueue.main.async {
            self.onFinish = onFinish
            self.synthesizer.stopSpeaking(at: .immediate)

            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = 0.48
            utterance.voice = AVSpeechSynthesisVoice(language: self.voiceLanguage(for: text))
            self.synthesizer.speak(utterance)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishSpeaking()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishSpeaking()
    }

    private func finishSpeaking() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.finishSpeaking()
            }
            return
        }

        let completion = onFinish
        onFinish = nil
        completion?()
    }

    private func voiceLanguage(for text: String) -> String {
        text.unicodeScalars.contains { scalar in
            (0xAC00...0xD7AF).contains(Int(scalar.value))
        } ? "ko-KR" : "en-US"
    }
}
