import Foundation
import AVFoundation

/// A single warning bell played at workout / phase transitions for non-interval
/// workouts — strength start, guided warm-up, guided cool-down, and end
/// (feedback batch 7 item 9). It cues the user to start or stop when they're not
/// looking at the phone. Intervals (HIIT) have their own richer cues via
/// `IntervalCues`, and boxing keeps its own round bell — neither goes through here.
///
/// Gated by the "Workout sounds" setting at every call site. Reuses the bundled
/// `warning-bell.mp3` (no new assets) and ducks other audio like `IntervalCues`.
@MainActor
enum WorkoutCues {
    private static let bell: AVAudioPlayer? = {
        guard let url = Bundle.main.url(forResource: "warning-bell", withExtension: "mp3") else { return nil }
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.prepareToPlay()
        return p
    }()

    /// Play the transition bell + a light haptic. No-op when `enabled` is false.
    static func transition(enabled: Bool) {
        guard enabled else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers, .mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        bell?.currentTime = 0
        bell?.play()
        Haptics.restComplete()
    }
}
