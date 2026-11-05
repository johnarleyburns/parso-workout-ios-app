import Foundation
import CadenceCore
import CadenceFeatures

extension WatchWorkoutManager {
    /// Provenance of the current strength pause (nil when not paused). Only
    /// explicit user actions or an unexpected HealthKit transition set it.
    var strengthPauseOrigin: WatchPauseOrigin? { strengthPause.origin }
    /// The only path that pauses or resumes a strength session.
    func userToggleStrengthPause(origin: WatchPauseOrigin) {
        guard workoutType == "strength", let s = session else { return }
        if s.state == .running {
            guard strengthPause.userPause(origin) else { return }
            s.pause(); elapsedTracker.startPause()
        } else if s.state == .paused {
            strengthPause.userResume()
            s.resume(); elapsedTracker.resume()
        }
    }
    var effectiveElapsed: TimeInterval {
        guard let sessionStart else { return 0 }
        return elapsedTracker.elapsed(since: sessionStart)
    }
    /// Elapsed time of the cardio session the user is running, independent of
    /// the shared `HKWorkoutSession` start used for strength heart-rate relay.
    var cardioElapsed: TimeInterval {
        guard let cardioSessionStart else { return effectiveElapsed }
        if let record = cardioInactivity.record { return record.activeDuration(endedAt: Date()) } // excludes paused time
        return max(0, Date().timeIntervalSince(cardioSessionStart))
    }
}
