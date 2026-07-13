import Foundation
import Observation
import CadenceCore

public extension Notification.Name {
    /// Posted when a past workout's date is edited from history (SessionView). Home
    /// observes it to bump `historyRefreshToken` so the coach snapshot / "This Week"
    /// strip recompute immediately — the `CoachSignature` keys on counts + token, not
    /// individual session dates, so a pure date edit would otherwise go unnoticed.
    static let workoutHistoryChanged = Notification.Name("cadence.workoutHistoryChanged")
}

/// The just-finished workout's summary, presented over Home (P1 #9).
public struct FinishedSummary: Identifiable {
    public let id = UUID()
    public let data: WorkoutSummaryData
    public init(data: WorkoutSummaryData) { self.data = data }
}

/// Tracks the one in-progress workout so Home can surface a Resume card and the
/// session can be finalized cleanly (field-testing §02, decision #8: a single
/// active session at a time). The full idle-watchdog UI integration lands with
/// the rebuilt strength screen (§04); this is the engine's app-level anchor.
///
/// Moved into CadenceFeatures (test-pyramid Phase 2) so its lifecycle + stamping
/// are unit-tested headlessly.
@Observable
public final class ActiveWorkoutModel {
    /// The active strength session, if any. nil when nothing is in progress.
    public var strengthSession: WorkoutSession?

    /// The just-finished workout's summary, presented over Home (P1 #9). Lifting
    /// it above the session screen lets the session pop *behind* the summary, so
    /// dismissing it (Done) reveals Home directly instead of flashing the session.
    public var finishedSummary: FinishedSummary?

    /// Wall-clock timer for the active session (field-testing §02).
    public private(set) var clock = WorkoutClock()

    public init() {}

    public var isActive: Bool { strengthSession != nil }

    /// True while the active session's clock is paused (field-testing Round 4 A1).
    public var isPaused: Bool { clock.isPaused }

    public func startStrength(_ session: WorkoutSession) {
        strengthSession = session
        clock = WorkoutClock(startedAt: session.date)
    }

    /// Pauses the active session's wall-clock (also freezes the idle watchdog).
    public func pause() { clock.pause() }

    /// Resumes the active session's wall-clock.
    public func resume() { clock.resume() }

    /// Marks the active strength session finished: stamps `endedAt` on the model
    /// and clears the active reference. The caller saves its `ModelContext`.
    public func endStrength() {
        guard let session = strengthSession else { return }
        clock.end()
        session.endedAt = clock.endedAt
        session.updatedAt = Date()
        strengthSession = nil
    }
}
