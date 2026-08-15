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
    public let session: WorkoutSession?
    public init(data: WorkoutSummaryData, session: WorkoutSession? = nil) { self.data = data; self.session = session }
}

/// Why the active workout is paused. An `.auto` pause (idle watchdog, crash
/// recovery) resumes on the next user activity; a `.manual` pause stays until
/// the user taps Resume (launch-blockers plan, Phase 1a).
public enum PauseOrigin: Equatable, Sendable {
    case manual
    case auto
}

/// What the root-level workout cover is showing (launch-blockers plan, Phase 1b).
/// The live session and its finish summary share one `fullScreenCover(item:)` so
/// ending a workout swaps surface identity in place — Home never flashes between.
public enum ActiveSurface: Identifiable {
    case session(WorkoutSession)
    case summary(FinishedSummary)

    public var id: String {
        switch self {
        case .session(let s): return "session-\(s.id.uuidString)"
        case .summary(let f): return "summary-\(f.id.uuidString)"
        }
    }
}

/// Tracks the one in-progress workout so Home can surface a Resume card and the
/// session can be finalized cleanly (field-testing §02, decision #8: a single
/// active session at a time).
///
/// Lifecycle hard rule (decisions.md 2026-07-18): a workout is NEVER ended or
/// lost by the system. The only automatic action is a pause; ending requires an
/// explicit user tap. Crash/upgrade recovery re-adopts the session paused.
///
/// Moved into CadenceFeatures (test-pyramid Phase 2) so its lifecycle + stamping
/// are unit-tested headlessly.
@MainActor @Observable
public final class ActiveWorkoutModel {
    public let liveWorkout = LiveWorkoutCoordinator()
    /// The active strength session, if any. nil when nothing is in progress.
    public var strengthSession: WorkoutSession?

    /// The root-level workout cover's content. `.session` while training,
    /// `.summary` after an explicit end, nil when minimized/idle.
    public var presentedSurface: ActiveSurface?

    /// The just-finished workout's summary. Setting it flips the presented
    /// surface to `.summary` in place (session → summary, no Home flash);
    /// clearing it dismisses the cover.
    public var finishedSummary: FinishedSummary? {
        didSet {
            if let f = finishedSummary {
                presentedSurface = .summary(f)
            } else if case .summary = presentedSurface {
                presentedSurface = nil
            }
        }
    }

    /// Wall-clock timer for the active session (field-testing §02).
    public private(set) var clock = WorkoutClock()

    /// Why the clock is paused (nil while running).
    public private(set) var pauseOrigin: PauseOrigin?

    /// Heartbeat + recovery bookkeeping storage (injectable for tests).
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isActive: Bool { strengthSession != nil }

    /// True while the active session's clock is paused (field-testing Round 4 A1).
    public var isPaused: Bool { clock.isPaused }

    @discardableResult
    public func startStrength(_ session: WorkoutSession) -> Bool {
        guard liveWorkout.acquire(LiveWorkoutDescriptor(kind: .strength(sessionID: session.id), name: session.title.isEmpty ? "Workout" : session.title)) else { return false }
        strengthSession = session
        clock = WorkoutClock(startedAt: session.date)
        pauseOrigin = nil
        presentedSurface = .session(session)
        return true
    }

    /// Commits a strength recorder after the root coordinator has already
    /// reserved its lease. This is the only path Home uses after a final-boundary
    /// check, so session materialization cannot race another live start.
    @discardableResult
    public func startStrength(_ session: WorkoutSession, lease: LiveWorkoutLease) -> Bool {
        guard strengthSession == nil,
              liveWorkout.lease == lease,
              liveWorkout.adopt(lease, descriptor: LiveWorkoutDescriptor(
                kind: .strength(sessionID: session.id),
                name: session.title.isEmpty ? "Workout" : session.title)) else { return false }
        strengthSession = session
        clock = WorkoutClock(startedAt: session.date)
        pauseOrigin = nil
        presentedSurface = .session(session)
        return true
    }

    /// Presents the workout cover for the active session (Resume card tap).
    public func present() {
        guard let session = strengthSession else { return }
        presentedSurface = .session(session)
    }

    /// Hides the workout cover WITHOUT ending anything — the only way to Home
    /// mid-workout. The session stays active; Home shows the Resume card.
    public func minimize() {
        if case .session = presentedSurface { presentedSurface = nil }
    }

    /// Pauses the active session's wall-clock (also freezes the idle watchdog).
    public func pause(origin: PauseOrigin = .manual, now: Date = Date()) {
        guard !clock.isPaused else { return }
        clock.pause(now: now)
        pauseOrigin = origin
    }

    /// Resumes the active session's wall-clock.
    public func resume(now: Date = Date()) {
        clock.resume(now: now)
        pauseOrigin = nil
    }

    /// User activity resumes an automatic pause; a manual pause stays until the
    /// user taps Resume (launch-blockers decisions #1/#2).
    public func recordActivityAutoResume(now: Date = Date()) {
        guard isPaused, pauseOrigin == .auto else { return }
        resume(now: now)
    }

    /// Marks the active strength session finished: stamps `endedAt` on the model
    /// and clears the active reference. The caller saves its `ModelContext`.
    /// Deliberately leaves `presentedSurface` alone — the caller flips it to the
    /// summary (via `finishedSummary`) so the cover swaps without a Home flash.
    public func endStrength(now: Date = Date()) {
        guard let session = strengthSession else { return }
        clock.end(now: now)
        session.endedAt = clock.endedAt
        session.updatedAt = Date()
        strengthSession = nil
        pauseOrigin = nil
        WorkoutHeartbeatStore.clear(defaults: defaults)
        if let lease = liveWorkout.lease { _ = liveWorkout.release(lease) }
    }

    /// Clears the active workout and its cover without stamping `endedAt`
    /// (delete flow — the session model is being soft-deleted by the caller).
    public func discardActive() {
        if strengthSession != nil, let lease = liveWorkout.lease { _ = liveWorkout.release(lease) }
        strengthSession = nil
        pauseOrigin = nil
        presentedSurface = nil
        WorkoutHeartbeatStore.clear(defaults: defaults)
    }

    /// Crash/upgrade recovery (Phase 1e): re-adopts an in-progress session
    /// **paused** (`.auto`) and **not presented** — Home shows the Resume card.
    /// The clock is reconstructed so the dead gap [lastAlive, now] is folded in
    /// as a paused span: elapsed at adoption equals elapsed at the last
    /// heartbeat, and only grows again after the user resumes.
    public func adopt(_ session: WorkoutSession, heartbeat: WorkoutHeartbeat?, now: Date = Date()) {
        let elapsed = ActiveSessionRecovery.adoptedElapsed(sessionID: session.id, heartbeat: heartbeat)
        let gross = max(0, now.timeIntervalSince(session.date))
        strengthSession = session
        _ = liveWorkout.acquire(LiveWorkoutDescriptor(kind: .strength(sessionID: session.id), name: session.title.isEmpty ? "Workout" : session.title))
        clock = WorkoutClock(startedAt: session.date,
                             pausedAccumulated: max(0, gross - elapsed),
                             pausedSince: now)
        pauseOrigin = .auto
        presentedSurface = nil
    }

    /// Records the liveness heartbeat for the active session (5 s tick + scene
    /// transitions). No-op when nothing is active.
    public func writeHeartbeat(now: Date = Date()) {
        guard let session = strengthSession else { return }
        WorkoutHeartbeatStore.write(
            WorkoutHeartbeat(sessionID: session.id,
                             lastAlive: now,
                             elapsed: clock.elapsed(now: now),
                             isPaused: clock.isPaused),
            defaults: defaults)
    }
}
