import Foundation
import Observation
import CadenceCore

/// Tracks the one in-progress workout so Home can surface a Resume card and the
/// session can be finalized cleanly (field-testing §02, decision #8: a single
/// active session at a time). The full idle-watchdog UI integration lands with
/// the rebuilt strength screen (§04); this is the engine's app-level anchor.
@Observable
final class ActiveWorkoutModel {
    /// The active strength session, if any. nil when nothing is in progress.
    var strengthSession: WorkoutSession?

    /// Wall-clock timer for the active session (field-testing §02).
    private(set) var clock = WorkoutClock()

    var isActive: Bool { strengthSession != nil }

    func startStrength(_ session: WorkoutSession) {
        strengthSession = session
        clock = WorkoutClock(startedAt: session.date)
    }

    /// Marks the active strength session finished: stamps `endedAt` on the model
    /// and clears the active reference. The caller saves its `ModelContext`.
    func endStrength() {
        guard let session = strengthSession else { return }
        clock.end()
        session.endedAt = clock.endedAt
        session.updatedAt = Date()
        strengthSession = nil
    }
}
