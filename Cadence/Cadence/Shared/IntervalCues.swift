import Foundation
import AVFoundation
import CadenceCore

/// Non-visual interval cues (field-testing §06/round 4): haptics + bundled bell
/// sounds on every transition, a 30-second warning bell, and optional spoken
/// announcements — so the signal works with the phone in a pocket or for
/// low-vision use. All cue audio mixes with the user's background audio via
/// `WorkoutAudioSession` — it never pauses or ducks it.
///
/// Boxing keeps its own round bell (`opening-closing-bell.mp3` + `warning-bell.mp3`).
/// Non-boxing intervals use soft system beeps for a calmer experience.
@MainActor
final class IntervalCues {
    var spokenEnabled = false
    /// When true, use the bundled MP3 bells (boxing). When false, use soft system beeps.
    var isBoxing = false
    private let synth = AVSpeechSynthesizer()
    private var sessionActive = false

    /// Opening/closing bell (round start & end) and the 30-second warning bell,
    /// from the bundled MP3s. Preloaded so playback is instant. Only used for boxing.
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
        WorkoutAudioSession.configureForCues()
        sessionActive = true
    }

    /// Marks the cue session inactive. With the `.playback` category we hold the
    /// audio session while cues are running; deactivating hands it back to any
    /// concurrent audio app (music, podcast) that was mixing in.
    func deactivate() {
        WorkoutAudioSession.deactivateSession()
        sessionActive = false
    }

    /// Fire on entering a new phase — boxing: opening/closing bell; non-boxing: soft tick.
    func phaseChanged(to kind: IntervalPhaseKind, label: String) {
        if isBoxing {
            play(bell)
        } else {
            activateSession()
            TonePlayer.playTick()
        }
        switch kind {
        case .work: Haptics.prAchieved()
        case .rest, .cooldown: Haptics.restComplete()
        case .warmup: Haptics.setLogged()
        }
        if spokenEnabled { speak(spokenPhrase(for: kind, label: label)) }
    }

    /// 30-second warning during a work phase. Boxing: warning bell; non-boxing: soft alert beep.
    func warning() {
        if isBoxing {
            play(warningBell)
        } else {
            activateSession()
            TonePlayer.playAlert()
        }
        Haptics.restComplete()
    }

    /// Final-3-seconds tick (haptic only; the bells/beeps carry the audio).
    func countdownTick() {
        Haptics.setLogged()
    }

    func completed() {
        if isBoxing {
            play(bell)
        } else {
            activateSession()
            TonePlayer.playAlert()
        }
        Haptics.prAchieved()
        if spokenEnabled { speak("Workout complete") }
    }

    private func speak(_ text: String) {
        activateSession()
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
