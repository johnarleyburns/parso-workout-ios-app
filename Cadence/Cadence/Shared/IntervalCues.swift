import Foundation
import AVFoundation
import AudioToolbox
import CadenceCore

/// Non-visual interval cues (field-testing §06, decision #23): haptics + audio
/// beeps on every transition, with optional spoken announcements — so the
/// signal works with the phone in a pocket or for low-vision use. Uses system
/// sounds (no bundled assets) and an audio session that ducks other audio.
@MainActor
final class IntervalCues {
    var spokenEnabled = false
    private let synth = AVSpeechSynthesizer()
    private var sessionActive = false

    private func activateSession() {
        guard !sessionActive else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers, .mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        sessionActive = true
    }

    func deactivate() {
        guard sessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }

    /// Fire on entering a new phase.
    func phaseChanged(to kind: IntervalPhaseKind, label: String) {
        activateSession()
        switch kind {
        case .work:
            AudioServicesPlaySystemSound(1057)   // a bright start tone
            Haptics.prAchieved()
        case .rest, .cooldown:
            AudioServicesPlaySystemSound(1075)   // softer tone
            Haptics.restComplete()
        case .warmup:
            AudioServicesPlaySystemSound(1075)
            Haptics.setLogged()
        }
        if spokenEnabled { speak(spokenPhrase(for: kind, label: label)) }
    }

    /// Fire on each of the final 3 seconds of a phase.
    func countdownTick() {
        activateSession()
        AudioServicesPlaySystemSound(1103)       // tick
        Haptics.setLogged()
    }

    func completed() {
        activateSession()
        AudioServicesPlaySystemSound(1025)
        Haptics.prAchieved()
        if spokenEnabled { speak("Workout complete") }
    }

    private func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }

    private func spokenPhrase(for kind: IntervalPhaseKind, label: String) -> String {
        switch kind {
        case .work: return label.replacingOccurrences(of: "·", with: ",")
        case .rest: return "Rest"
        case .warmup: return "Warm up"
        case .cooldown: return "Cool down"
        }
    }
}
