import Foundation
import AVFoundation

/// A single warning bell played at workout / phase transitions for non-interval
/// workouts — strength start, guided warm-up, guided cool-down, and end
/// (feedback batch 7 item 9). It cues the user to start or stop when they're not
/// looking at the phone. Intervals (HIIT) have their own richer cues via
/// `IntervalCues`, and boxing keeps its own round bell — neither goes through here.
///
/// Gated by the "Workout sounds" setting at every call site. Reuses the bundled
/// `warning-bell.mp3` (no new assets). Non-boxing workouts get short engineered
/// tones via `TonePlayer` (replaces `AudioServicesPlaySystemSound` for background
/// capability). All cue audio mixes with the user's background audio via
/// `WorkoutAudioSession` — it never pauses or ducks it.
///
/// FR-8 follow-up: non-boxing workouts get soft tones instead of bells.
/// Start = 3 countdown ticks (1s apart) → 1 start alert, or one alert when
/// the workout starts immediately.
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
        WorkoutAudioSession.configureForCues()
        bell?.currentTime = 0
        bell?.play()
        Haptics.restComplete()
    }

    /// Soft 3-2-1 countdown tones (1 s apart) followed by a start alert.
    /// Gated by `enabled`. No-op when false.
    static func startBeepSequence(enabled: Bool) {
        guard enabled else { return }
        WorkoutAudioSession.configureForCues()
        TonePlayer.countdownStart()
    }

    /// Single start alert for immediate launches, such as skipping warm-up.
    static func singleStart(enabled: Bool) {
        guard enabled else { return }
        WorkoutAudioSession.configureForCues()
        TonePlayer.singleStart()
    }

    static func cancelPendingSounds() {
        TonePlayer.cancelPending()
    }

    /// Three rapid soft tones (0.15 s apart) to signal workout end.
    /// Gated by `enabled`. No-op when false.
    static func endBeepSequence(enabled: Bool) {
        guard enabled else { return }
        WorkoutAudioSession.configureForCues()
        TonePlayer.rapidEnd()
    }
}
