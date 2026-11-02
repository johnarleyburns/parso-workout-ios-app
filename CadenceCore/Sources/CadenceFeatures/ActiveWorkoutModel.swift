import Foundation
import Observation
import CadenceCore

public extension Notification.Name {
    /// Posted when a past workout's date is edited from history (SessionView). Home
    /// observes it to bump `historyRefreshToken` so the coach snapshot / "This Week"
    /// strip recompute immediately — the `CoachSignature` keys on counts + token, not
    /// individual session dates, so a pure date edit would otherwise go unnoticed.
    static let workoutHistoryChanged = Notification.Name("cadence.workoutHistoryChanged")
    /// A lightweight per-set volume callback. The set is already persisted when
    /// this is posted; consumers update their projections without rebuilding the
    /// whole coach pipeline on the UI thread.
    /// Posted once (object: session UUID) after an accepted end_session replacement
    /// changed a session's persisted heart-rate series. Consumers refresh summary,
    /// History, This Week, Watch snapshot and Health backup idempotently.
    static let workoutHeartRateFinalized = Notification.Name("cadence.workoutHeartRateFinalized")
    static let workoutVolumeChanged = Notification.Name("cadence.workoutVolumeChanged")
}

public struct WorkoutVolumeChange: Sendable {
    public let sessionID: UUID
    public let date: Date
    public let delta: [MuscleGroup: Double]

    public init(sessionID: UUID, date: Date, delta: [MuscleGroup: Double]) {
        self.sessionID = sessionID
        self.date = date
        self.delta = delta
    }
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

/// Why a strength session ended; persisted as `WorkoutSession.endReasonRaw`.
public enum StrengthEndReason: String, Sendable, Equatable {
    case user, inactivity
}

public enum FinalizeResult: Equatable, Sendable {
    /// This call ended the session.
    case finalized
    /// The session was not active (already ended, or a different session): nothing changed.
    case alreadyEnded
}

/// Truthful notice shown at the next UI opportunity after an inactivity auto-end.
public struct StrengthInactivityNotice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let endedAt: Date
    public let timeoutMinutes: Int
    public var message: String {
        String(localized: "Ended after \(timeoutMinutes) minutes inactive", bundle: .module)
    }
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
    /// Shared platform projection for the currently visible rest timer.
    public var restEndsAt: Date?
    public var nextExercise: String?
    /// Presentation-only identity for the next pending set shown on the Live
    /// Activity. It is intentionally not persisted or used as a store key.
    public var nextSetSummary: String?
    public var nextSetToken: String?

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

    /// Side effects owned by the app (stop the phone-owned Watch HR workout once, flush HR,
    /// Health save, linked scheduled workout, Live Activity). Invoked exactly once per
    /// finalization, before the active state is cleared. No SwiftUI view is required.
    @ObservationIgnored public var strengthFinalizer: (@MainActor (WorkoutSession, StrengthEndReason) -> Void)?

    /// Set when a session was auto-ended for inactivity; the UI shows it, then clears it.
    public var inactivityNotice: StrengthInactivityNotice?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isActive: Bool { strengthSession != nil }

    /// Session-owned phone HR recorder, created lazily for (and keyed to) the
    /// active strength session, so it exists for both fresh starts and recovery
    /// adoption and outlives any SwiftUI view. Retained after `endStrength` so
    /// the caller can run the final flush; replaced when another session starts.
    @ObservationIgnored private var recorder: PhoneStrengthHeartRateRecorder?
    public var heartRateRecorder: PhoneStrengthHeartRateRecorder? {
        if let session = strengthSession {
            if recorder?.sessionID != session.id { recorder = PhoneStrengthHeartRateRecorder(session: session) }
        }
        return recorder
    }

    /// Session whose final heart-rate flush failed and awaits retry. While set,
    /// the summary shows honest pending/retry copy instead of a final zero.
    public private(set) var heartRatePendingSessionID: UUID?

    /// Final, awaitable flush of the session-owned recorder. Idempotent. On
    /// failure the data stays in the recorder and the session is flagged pending.
    @discardableResult
    public func finalizeHeartRate(profile: CardioIntensityProfile, sessionID: UUID) -> Bool {
        guard let recorder, recorder.sessionID == sessionID else {
            if heartRatePendingSessionID == sessionID { heartRatePendingSessionID = nil }
            return true
        }
        let ok = recorder.finalize(profile: profile)
        if ok {
            if heartRatePendingSessionID == sessionID { heartRatePendingSessionID = nil }
        } else {
            heartRatePendingSessionID = sessionID
        }
        return ok
    }

    /// True while the active session's clock is paused (field-testing Round 4 A1).
    public var isPaused: Bool { clock.isPaused }

    @discardableResult
    public func startStrength(_ session: WorkoutSession, now: Date = Date()) -> Bool {
        guard liveWorkout.acquire(LiveWorkoutDescriptor(kind: .strength(sessionID: session.id), name: session.title.isEmpty ? String(localized: "Workout", bundle: .module) : session.title)) else { return false }
        strengthSession = session
        restEndsAt = nil
        nextExercise = nil
        nextSetSummary = nil
        nextSetToken = nil
        clock = WorkoutClock(startedAt: session.date)
        pauseOrigin = nil
        if session.lastMeaningfulActivityAt == nil { session.lastMeaningfulActivityAt = now }
        presentedSurface = .session(session)
        return true
    }

    /// Commits a strength recorder after the root coordinator has already
    /// reserved its lease. This is the only path Home uses after a final-boundary
    /// check, so session materialization cannot race another live start.
    @discardableResult
    public func startStrength(_ session: WorkoutSession, lease: LiveWorkoutLease, now: Date = Date()) -> Bool {
        guard strengthSession == nil,
              liveWorkout.lease == lease,
              liveWorkout.adopt(lease, descriptor: LiveWorkoutDescriptor(
                kind: .strength(sessionID: session.id),
                name: session.title.isEmpty ? String(localized: "Workout", bundle: .module) : session.title)) else { return false }
        strengthSession = session
        restEndsAt = nil
        nextExercise = nil
        nextSetSummary = nil
        nextSetToken = nil
        clock = WorkoutClock(startedAt: session.date)
        pauseOrigin = nil
        if session.lastMeaningfulActivityAt == nil { session.lastMeaningfulActivityAt = now }
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

    /// Records a genuine user action (see `StrengthActivityEvent`) as the new inactivity
    /// baseline. Lifecycle hooks (scene phase, timers, HR, Live Activity) must NOT call this.
    public func recordMeaningfulActivity(_ event: StrengthActivityEvent, now: Date = Date()) {
        guard let session = strengthSession else { return }
        var state = StrengthInactivityPolicy.State(lastMeaningfulActivityAt: session.lastMeaningfulActivityAt ?? now)
        state.record(event, at: now)
        session.lastMeaningfulActivityAt = state.lastMeaningfulActivityAt
        session.updatedAt = now
    }

    /// Ends the active strength session at the inactivity deadline when it has expired.
    /// Not activity: callable from foreground, launch recovery, and timers. Idempotent.
    @discardableResult
    public func reconcileStrengthInactivity(enabled: Bool, timeoutMinutes: Int,
                                            now: Date = Date()) -> FinalizeResult? {
        guard let session = strengthSession,
              !session.isLogged,
              let last = session.lastMeaningfulActivityAt else { return nil }
        let state = StrengthInactivityPolicy.State(lastMeaningfulActivityAt: last)
        guard case let .end(deadline) = StrengthInactivityPolicy.evaluate(
            state: state, now: now, timeoutMinutes: timeoutMinutes, enabled: enabled) else { return nil }
        let result = finalizeStrength(sessionID: session.id, endedAt: deadline,
                                      reason: .inactivity, now: now)
        if result == .finalized {
            inactivityNotice = StrengthInactivityNotice(id: UUID(), sessionID: session.id,
                                                        endedAt: deadline, timeoutMinutes: max(1, timeoutMinutes))
        }
        return result
    }

    /// One idempotent finalization path. `endedAt` is stamped verbatim (the deadline for
    /// inactivity); `inactivityAutoEndedAt` records the actual reconciliation time.
    /// Never deletes or discards sets.
    @discardableResult
    public func finalizeStrength(sessionID: UUID, endedAt: Date, reason: StrengthEndReason,
                                 now: Date = Date()) -> FinalizeResult {
        guard let session = strengthSession, session.id == sessionID else { return .alreadyEnded }
        strengthFinalizer?(session, reason)
        endStrength(now: endedAt)
        session.endReasonRaw = reason.rawValue
        if reason == .inactivity { session.inactivityAutoEndedAt = now }
        if reason == .inactivity { presentedSurface = nil }
        return .finalized
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
        if session.endReasonRaw == nil { session.endReasonRaw = StrengthEndReason.user.rawValue }
        strengthSession = nil
        restEndsAt = nil
        nextExercise = nil
        nextSetSummary = nil
        nextSetToken = nil
        pauseOrigin = nil
        WorkoutHeartbeatStore.clear(defaults: defaults)
        if let lease = liveWorkout.lease { _ = liveWorkout.release(lease) }
    }

    /// Clears the active workout and its cover without stamping `endedAt`
    /// (delete flow — the session model is being soft-deleted by the caller).
    public func discardActive() {
        if strengthSession != nil, let lease = liveWorkout.lease { _ = liveWorkout.release(lease) }
        strengthSession = nil
        restEndsAt = nil
        nextExercise = nil
        nextSetSummary = nil
        nextSetToken = nil
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
        // Legacy session (pre-inactivity metadata): baseline at the last proof of life so the
        // returning user cannot inherit an unbounded active workout; reconciliation then ends it
        // at lastAlive + timeout. Existing metadata is never touched (adoption is not activity).
        if session.lastMeaningfulActivityAt == nil {
            session.lastMeaningfulActivityAt = heartbeat?.sessionID == session.id
                ? (heartbeat?.lastAlive ?? session.date) : session.date
        }
        strengthSession = session
        nextSetSummary = nil
        nextSetToken = nil
        _ = liveWorkout.acquire(LiveWorkoutDescriptor(kind: .strength(sessionID: session.id), name: session.title.isEmpty ? String(localized: "Workout", bundle: .module) : session.title))
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
