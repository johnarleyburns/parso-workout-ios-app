import Foundation
import AVFoundation
import AudioToolbox
import CadenceCore

/// Non-visual interval cues (field-testing §06/round 4): haptics + bundled bell
/// sounds on every transition, a 30-second warning bell, and optional spoken
/// announcements — so the signal works with the phone in a pocket or for
/// low-vision use. The audio session ducks other audio.
@MainActor
final class IntervalCues {
    var spokenEnabled = false
    private let synth = AVSpeechSynthesizer()
    private var sessionActive = false

    /// Opening/closing bell (round start & end) and the 30-second warning bell,
    /// from the bundled MP3s. Preloaded so playback is instant.
    private let bell = IntervalCues.player(named: "opening-closing-bell")
    private let warningBell = IntervalCues.player(named: "warning-bell")

    private static func player(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return nil }
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.prepareToPlay()
        return p
    }

    private func play(_ player: AVAudioPlayer?) {
        activateSession()
        player?.currentTime = 0
        player?.play()
    }

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

    /// Fire on entering a new phase — the opening bell starts work, the closing
    /// bell ends a round (rest/cooldown). Same bell file for both.
    func phaseChanged(to kind: IntervalPhaseKind, label: String) {
        play(bell)
        switch kind {
        case .work: Haptics.prAchieved()
        case .rest, .cooldown: Haptics.restComplete()
        case .warmup: Haptics.setLogged()
        }
        if spokenEnabled { speak(spokenPhrase(for: kind, label: label)) }
    }

    /// 30-second warning during a work phase.
    func warning() {
        play(warningBell)
        Haptics.restComplete()
    }

    /// Final-3-seconds tick (haptic only; the bells carry the audio).
    func countdownTick() {
        Haptics.setLogged()
    }

    func completed() {
        play(bell)
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
