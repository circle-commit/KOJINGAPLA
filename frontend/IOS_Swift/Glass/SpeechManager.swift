import AVFoundation

final class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    func speak(_ text: String, onFinish: (() -> Void)? = nil) {
        guard !text.isEmpty else { return }

        DispatchQueue.main.async {
            self.onFinish = onFinish
            self.synthesizer.stopSpeaking(at: .immediate)

            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = 0.48
            utterance.voice = self.bestVoice(for: self.voiceLanguage(for: text))
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

    // Guidance must be audible with the ringer muted and over other audio.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    // AVSpeechSynthesisVoice(language:) returns the compact default voice even
    // when the user has enhanced/premium neural voices installed, so pick the
    // highest-quality installed voice for the language instead.
    private func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        if let cached = voiceCache[language] {
            return cached
        }

        let voice = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: language)

        if let voice {
            voiceCache[language] = voice
        }
        return voice
    }

    private func voiceLanguage(for text: String) -> String {
        text.unicodeScalars.contains { scalar in
            (0xAC00...0xD7AF).contains(Int(scalar.value))
        } ? "ko-KR" : "en-US"
    }
}
