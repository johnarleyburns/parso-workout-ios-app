import Foundation
import AVFoundation
import AudioToolbox

/// A single warning bell played at workout / phase transitions for non-interval
/// workouts — strength start, guided warm-up, guided cool-down, and end
/// (feedback batch 7 item 9). It cues the user to start or stop when they're not
/// looking at the phone. Intervals (HIIT) have their own richer cues via
/// `IntervalCues`, and boxing keeps its own round bell — neither goes through here.
///
/// Gated by the "Workout sounds" setting at every call site. Reuses the bundled
/// `warning-bell.mp3` (no new assets) and ducks other audio like `IntervalCues`.
///
/// FR-8 follow-up: non-boxing workouts get soft system beeps instead of bells.
/// Start = 3 countdown ticks (1s apart) → 1 start beep.
/// End = 3 rapid ticks.
@MainActor
enum WorkoutCues {
    private static let bell: AVAudioPlayer? = {
        guard let url = Bundle.main.url(forResource: "warning-bell", withExtension: "mp3") else { return nil }
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.prepareToPlay()
        return p
    }()

    /// Play the transition bell + a light haptic. No-op when `enabled` is false.
    /// Boxing only — non-boxing uses `startBeepSequence` / `endBeepSequence`.
    static func transition(enabled: Bool) {
        guard enabled else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers, .mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        bell?.currentTime = 0
        bell?.play()
        Haptics.restComplete()
    }

    /// Soft 3-2-1 countdown beeps (1 s apart) followed by a start beep.
    /// Gated by `enabled`. No-op when false.
    static func startBeepSequence(enabled: Bool) {
        guard enabled else { return }
        SoundBeep.countdownStart()
    }

    /// Three rapid soft beeps (0.15 s apart) to signal workout end.
    /// Gated by `enabled`. No-op when false.
    static func endBeepSequence(enabled: Bool) {
        guard enabled else { return }
        SoundBeep.rapidEnd()
    }
}

// MARK: - System sound beeps (AudioServicesPlaySystemSound)

private enum SoundBeep {
    /// Short low tick — used for countdown and rapid-end sequences.
    static let tick: SystemSoundID = 1104
    /// Short higher-pitched beep — used for start and 30 s warning.
    static let alert: SystemSoundID = 1057

    /// 3 ticks at 1 s intervals → 1 start alert.
    static func countdownStart() {
        // Tick 1 (immediate)
        AudioServicesPlaySystemSound(tick)
        // Tick 2 (after 1 s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            AudioServicesPlaySystemSound(tick)
        }
        // Tick 3 (after 2 s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            AudioServicesPlaySystemSound(tick)
        }
        // Start beep (after 3 s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            AudioServicesPlaySystemSound(alert)
            Haptics.restComplete()
        }
    }

    /// 3 rapid ticks at 0.15 s intervals.
    static func rapidEnd() {
        AudioServicesPlaySystemSound(tick)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AudioServicesPlaySystemSound(tick)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            AudioServicesPlaySystemSound(tick)
            Haptics.restComplete()
        }
    }
}
