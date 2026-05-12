import AVFoundation

final class SpeechManager {
    private let synthesizer = AVSpeechSynthesizer()
    private let queue = DispatchQueue(label: "glass.speech.queue")

    func speak(_ text: String) {
        guard !text.isEmpty else { return }

        queue.async {
            self.synthesizer.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = 0.48
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            self.synthesizer.speak(utterance)
        }
    }
}
