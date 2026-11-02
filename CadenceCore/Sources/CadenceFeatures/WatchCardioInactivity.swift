import Foundation
import CadenceCore

/// Durable inactivity state for one Watch-owned cardio session (never the strength record).
/// Only supported cardio sessions get one; swim, monitoring and unknown sensor states
/// deliberately have none (documented fallback: the existing 4-hour orphan recovery and the
/// user's explicit End apply, because swim has no reliable motion/HR evidence under water).
public struct WatchCardioInactivityRecord: Codable, Sendable, Equatable {
    public let sessionGeneration: UUID
    public let type: CardioType
    public var evidence: CardioActivityEvidence
    public var pauseOrigin: CardioPauseOrigin?
    public var autoPausedAt: Date?
    /// Wall-clock cardio start; survives relaunch so the summary can be rebuilt.
    public var startedAt: Date
    /// Completed paused seconds (manual + resumed automatic) excluded from duration.
    public var pausedAccumulated: TimeInterval
    /// When a manual pause began (accounting only; manual pause never terminal-ends).
    public var manualPausedAt: Date?
    /// Whether the Watch cardio owns the `HKWorkoutSession` (false when layered over phone strength).
    public var ownsSession: Bool
    public var lastCountedDistance: Double

    public init(sessionGeneration: UUID = UUID(), type: CardioType, evidence: CardioActivityEvidence,
                pauseOrigin: CardioPauseOrigin? = nil, autoPausedAt: Date? = nil,
                startedAt: Date, pausedAccumulated: TimeInterval = 0, manualPausedAt: Date? = nil,
                ownsSession: Bool = true, lastCountedDistance: Double = 0) {
        self.sessionGeneration = sessionGeneration; self.type = type; self.evidence = evidence
        self.pauseOrigin = pauseOrigin; self.autoPausedAt = autoPausedAt; self.startedAt = startedAt
        self.pausedAccumulated = pausedAccumulated; self.manualPausedAt = manualPausedAt
        self.ownsSession = ownsSession; self.lastCountedDistance = lastCountedDistance
    }

    var policyEvidence: CardioActivityEvidence {
        var e = evidence
        e.pauseOrigin = pauseOrigin
        e.autoPausedAt = pauseOrigin == .automatic ? autoPausedAt : nil
        return e
    }

    /// Next instant the policy acts (pause deadline while running; terminal deadline while
    /// auto-paused; nil for manual pause).
    public func nextDeadline() -> Date? {
        switch pauseOrigin {
        case .manual: return nil
        case .automatic: return autoPausedAt.map(CardioInactivityPolicy.terminalDeadline(autoPausedAt:))
        case nil: return policyEvidence.lastQualifyingEvidenceAt?.addingTimeInterval(CardioInactivityPolicy.runningTimeout)
        }
    }

    /// Non-paused seconds from start to `endedAt` (paused time excluded, never negative).
    public func activeDuration(endedAt: Date) -> TimeInterval {
        let gross = max(0, endedAt.timeIntervalSince(startedAt))
        let open: TimeInterval
        if let p = autoPausedAt, pauseOrigin == .automatic { open = max(0, endedAt.timeIntervalSince(p)) }
        else if let p = manualPausedAt, pauseOrigin == .manual { open = max(0, endedAt.timeIntervalSince(p)) }
        else { open = 0 }
        return max(0, gross - pausedAccumulated - open)
    }
}

/// Durable "ended automatically" notice reachable after relaunch.
public struct WatchCardioInactivityNotice: Codable, Sendable, Equatable {
    public let type: CardioType
    public let endedAt: Date
    public init(type: CardioType, endedAt: Date) { self.type = type; self.endedAt = endedAt }
}

public enum WatchCardioInactivityAction: Sendable, Equatable {
    case none
    case autoPause(at: Date)
    case autoEnd(at: Date)
}

public protocol WatchCardioInactivityStoring: AnyObject, Sendable {
    func load() -> WatchCardioInactivityRecord?
    func save(_ record: WatchCardioInactivityRecord?)
    func loadNotice() -> WatchCardioInactivityNotice?
    func saveNotice(_ notice: WatchCardioInactivityNotice?)
}

public final class InMemoryWatchCardioInactivityStore: WatchCardioInactivityStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var record: WatchCardioInactivityRecord?
    private var notice: WatchCardioInactivityNotice?
    public init() {}
    public func load() -> WatchCardioInactivityRecord? { lock.withLock { record } }
    public func save(_ r: WatchCardioInactivityRecord?) { lock.withLock { record = r } }
    public func loadNotice() -> WatchCardioInactivityNotice? { lock.withLock { notice } }
    public func saveNotice(_ n: WatchCardioInactivityNotice?) { lock.withLock { notice = n } }
}

public final class UserDefaultsWatchCardioInactivityStore: WatchCardioInactivityStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let recordKey = "watch.cardioInactivity.record", noticeKey = "watch.cardioInactivity.notice"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> WatchCardioInactivityRecord? {
        defaults.data(forKey: recordKey).flatMap { try? JSONDecoder().decode(WatchCardioInactivityRecord.self, from: $0) }
    }
    public func save(_ r: WatchCardioInactivityRecord?) {
        if let r, let d = try? JSONEncoder().encode(r) { defaults.set(d, forKey: recordKey) }
        else { defaults.removeObject(forKey: recordKey) }
    }
    public func loadNotice() -> WatchCardioInactivityNotice? {
        defaults.data(forKey: noticeKey).flatMap { try? JSONDecoder().decode(WatchCardioInactivityNotice.self, from: $0) }
    }
    public func saveNotice(_ n: WatchCardioInactivityNotice?) {
        if let n, let d = try? JSONEncoder().encode(n) { defaults.set(d, forKey: noticeKey) }
        else { defaults.removeObject(forKey: noticeKey) }
    }
}

/// Pure tracker over the durable record. The record, not any task, is the source of truth.
/// Passive events (relay heartbeats, repeated/stale builder samples, redraws) are never evidence.
public struct WatchCardioInactivityTracker: Sendable {
    public static let minimumDistanceStep: Double = 10
    public let store: WatchCardioInactivityStoring
    public init(store: WatchCardioInactivityStoring = UserDefaultsWatchCardioInactivityStore()) { self.store = store }

    public var record: WatchCardioInactivityRecord? { store.load() }

    /// Sensor profile for a cardio session; nil means unsupported (no record).
    public static func profile(type: CardioType, isSwim: Bool, gps: Bool, heartRate: Bool) -> CardioSensorProfile? {
        if isSwim || type == .swim { return nil }
        if gps { return .outdoor }
        return heartRate ? .indoor : .timerOnly
    }

    @discardableResult
    public func begin(type: CardioType, profile: CardioSensorProfile?, ownsSession: Bool,
                      now: Date) -> WatchCardioInactivityRecord? {
        guard let profile else { store.save(nil); return nil }
        let e = CardioActivityEvidence(lastUserActionAt: now, referenceStartAt: now, sensorProfile: profile)
        let r = WatchCardioInactivityRecord(type: type, evidence: e, startedAt: now, ownsSession: ownsSession)
        store.save(r)
        return r
    }

    public func clear() { store.save(nil) }

    /// Returns true when the record changed (deadline moved). Ignored when a deadline already
    /// passed (reconcile owns it), when paused, or when the event is passive.
    @discardableResult
    public func recordEvidence(_ event: CardioEvidenceEvent, at: Date, enabled: Bool = true) -> Bool {
        guard var r = record, r.pauseOrigin == nil else { return false }
        if case .autoPause = CardioInactivityPolicy.decide(evidence: r.policyEvidence, now: at, enabled: enabled) { return false }
        switch event {
        case .userAction:
            r.evidence.lastUserActionAt = max(r.evidence.lastUserActionAt ?? at, at)
        case .distance(let total):
            guard r.evidence.sensorProfile == .outdoor else { return false } // indoor distance is unreliable
            guard total.isFinite, total >= r.lastCountedDistance + Self.minimumDistanceStep else { return false }
            r.lastCountedDistance = total
            guard r.evidence.sensorProfile == .outdoor else { store.save(r); return false }
            r.evidence.lastDistanceProgressAt = max(r.evidence.lastDistanceProgressAt ?? at, at)
        case .motion:
            r.evidence.lastMotionAt = max(r.evidence.lastMotionAt ?? at, at)
        case .heartRate(let bpm, let sampleAt, let resting, let maxHR):
            guard CardioInactivityPolicy.isQualifyingHeartRate(
                bpm: bpm, sampleAt: sampleAt, receivedAt: at,
                previousQualifyingAt: r.evidence.lastQualifyingHeartRateAt,
                restingHeartRate: resting, maxHeartRate: maxHR) else { return false }
            r.evidence.lastQualifyingHeartRateAt = sampleAt
        case .passive:
            return false
        }
        store.save(r)
        return true
    }

    public func recordManualPause(at: Date) {
        guard var r = record, r.pauseOrigin == nil else { return }
        r.pauseOrigin = .manual; r.manualPausedAt = at
        store.save(r)
    }

    public func recordAutoPause(at: Date) {
        guard var r = record, r.pauseOrigin == nil else { return }
        r.pauseOrigin = .automatic; r.autoPausedAt = at
        store.save(r)
    }

    /// Explicit user resume: clears any pause and records a user action. Refused (false) when
    /// the automatic pause already passed its terminal deadline (reconcile ends it instead).
    @discardableResult
    public func recordResume(at: Date, enabled: Bool = true) -> Bool {
        guard var r = record, let origin = r.pauseOrigin else { return false }
        switch origin {
        case .automatic:
            guard let p = r.autoPausedAt else { return false }
            if enabled, at >= CardioInactivityPolicy.terminalDeadline(autoPausedAt: p) { return false }
            r.pausedAccumulated += max(0, at.timeIntervalSince(p))
        case .manual:
            if let p = r.manualPausedAt { r.pausedAccumulated += max(0, at.timeIntervalSince(p)) }
        }
        r.pauseOrigin = nil; r.autoPausedAt = nil; r.manualPausedAt = nil
        r.evidence.lastUserActionAt = at
        store.save(r)
        return true
    }

    /// What the owner must now do. Pure; compares `now` to stored evidence/deadlines.
    public func evaluate(now: Date, enabled: Bool) -> WatchCardioInactivityAction {
        guard let r = record else { return .none }
        switch CardioInactivityPolicy.decide(evidence: r.policyEvidence, now: now, enabled: enabled) {
        case .autoPause(let at): return .autoPause(at: at)
        case .autoEnd(let at): return .autoEnd(at: at)
        case .continueRunning, .continuePaused: return .none
        }
    }
}
