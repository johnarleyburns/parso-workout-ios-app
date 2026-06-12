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

    /// The just-finished workout's summary, presented over Home (P1 #9). Lifting
    /// it above the session screen lets the session pop *behind* the summary, so
    /// dismissing it (Done) reveals Home directly instead of flashing the session.
    var finishedSummary: FinishedSummary?

    /// Wall-clock timer for the active session (field-testing §02).
    private(set) var clock = WorkoutClock()

    var isActive: Bool { strengthSession != nil }

    /// True while the active session's clock is paused (field-testing Round 4 A1).
    var isPaused: Bool { clock.isPaused }

    func startStrength(_ session: WorkoutSession) {
        strengthSession = session
        clock = WorkoutClock(startedAt: session.date)
    }

    /// Pauses the active session's wall-clock (also freezes the idle watchdog).
    func pause() { clock.pause() }

    /// Resumes the active session's wall-clock.
    func resume() { clock.resume() }

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
