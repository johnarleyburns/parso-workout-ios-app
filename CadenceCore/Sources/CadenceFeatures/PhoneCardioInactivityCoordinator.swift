import Foundation
import CadenceCore

/// Why an iPhone-recorded cardio workout was ended without the user pressing End.
public enum PhoneCardioFinalizeReason: String, Codable, Sendable, Equatable {
    case inactivity
}

/// Every input a live recorder may report. Only the "active" cases count as user
/// activity; the `passive` cases exist so call sites classify explicitly and the
/// coordinator can prove they are ignored.
public enum CardioEvidenceEvent: Sendable, Equatable {
    /// Explicit user control: start, resume, lap, goal edit. Always counts.
    case userAction
    /// Cumulative GPS path distance. Counts only when it grows by a meaningful step.
    case distance(totalMeters: Double)
    /// Motion class change from CoreMotion (outdoor profile only).
    case motion
    /// A heart-rate sample; counts only if `CardioInactivityPolicy.isQualifyingHeartRate`.
    case heartRate(bpm: Double, sampleAt: Date, restingHR: Double?, maxHR: Double?)
    case passive(PassiveSource)

    public enum PassiveSource: String, Sendable, Equatable, CaseIterable {
        case timerTick, viewAppeared, scenePhase, render, locationAuthorization
        case heartRateReceiptOnly, watchRelayHeartbeat, duplicateLocationFix
    }
}

/// Durable metadata needed to restore/reconcile a parked or backgrounded recorder.
/// Raw route/HR stay in the recorder; only accounting and evidence timestamps persist.
public struct PhoneLiveCardioSession: Codable, Sendable, Equatable, Identifiable {
    public struct TerminalReceipt: Codable, Sendable, Equatable {
        public var endedAt: Date
        public var reason: PhoneCardioFinalizeReason
        public var finalized: Bool
        public init(endedAt: Date, reason: PhoneCardioFinalizeReason, finalized: Bool = false) {
            self.endedAt = endedAt; self.reason = reason; self.finalized = finalized
        }
    }

    public var id: UUID
    public var type: CardioType
    /// "record", "outdoor" or "swim".
    public var route: String
    public var start: Date
    public var sensorProfile: CardioSensorProfile
    /// The `autoPause` preference captured at start.
    public var autoPauseEnabled: Bool
    public var lastUserActionAt: Date?
    public var lastDistanceProgressAt: Date?
    public var lastMotionAt: Date?
    public var lastQualifyingHeartRateAt: Date?
    /// Last cumulative distance that counted as progress (monotonic).
    public var lastCountedDistance: Double
    public var inactivity: CardioInactivityState
    /// Completed paused time (manual + automatic) excluded from active duration.
    public var pausedAccumulated: TimeInterval
    public var receipt: TerminalReceipt?

    public init(id: UUID = UUID(), type: CardioType, route: String, start: Date,
                sensorProfile: CardioSensorProfile, autoPauseEnabled: Bool) {
        self.id = id; self.type = type; self.route = route; self.start = start
        self.sensorProfile = sensorProfile; self.autoPauseEnabled = autoPauseEnabled
        self.lastCountedDistance = 0
        self.inactivity = CardioInactivityState()
        self.pausedAccumulated = 0
    }

    public var isPaused: Bool { inactivity.pausedAt != nil }

    var evidence: CardioActivityEvidence {
        CardioActivityEvidence(lastUserActionAt: lastUserActionAt,
                               lastDistanceProgressAt: lastDistanceProgressAt,
                               lastMotionAt: lastMotionAt,
                               lastQualifyingHeartRateAt: lastQualifyingHeartRateAt,
                               pauseOrigin: inactivity.pauseOrigin,
                               autoPausedAt: inactivity.pauseOrigin == .automatic ? inactivity.pausedAt : nil,
                               referenceStartAt: start, sensorProfile: sensorProfile)
    }

    /// Non-paused seconds between start and `endedAt`. Used for saved intensity.
    public func activeDuration(endedAt: Date) -> TimeInterval {
        let gross = max(0, endedAt.timeIntervalSince(start))
        let current = inactivity.pausedAt.map { max(0, endedAt.timeIntervalSince($0)) } ?? 0
        return max(0, gross - pausedAccumulated - current)
    }
}

/// Real side effects, implemented by the app (GPS/clock/Watch/Health/SwiftData).
@MainActor
public protocol PhoneCardioLifecycleActions: AnyObject {
    /// Pause clock/recorder/GPS (and Watch per ownership) as of `at` (the deadline).
    func pauseForInactivity(session: PhoneLiveCardioSession, at: Date)
    /// Stop GPS/HR/Watch, save the workout ending at `endedAt`, enqueue Health backup
    /// once, clear parked state. Must be idempotent per `sessionID`.
    func finalizePhoneCardio(sessionID: UUID, endedAt: Date,
                             reason: PhoneCardioFinalizeReason) async
}

/// Durable single-slot store for the live session (UserDefaults in the app).
@MainActor
public protocol PhoneLiveCardioStoring: AnyObject {
    func load() -> PhoneLiveCardioSession?
    func save(_ session: PhoneLiveCardioSession?)
}

@MainActor
public final class InMemoryPhoneLiveCardioStore: PhoneLiveCardioStoring {
    public private(set) var stored: PhoneLiveCardioSession?
    public init(_ initial: PhoneLiveCardioSession? = nil) { stored = initial }
    public func load() -> PhoneLiveCardioSession? { stored }
    public func save(_ session: PhoneLiveCardioSession?) { stored = session }
}

@MainActor
public final class UserDefaultsPhoneLiveCardioStore: PhoneLiveCardioStoring {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "phone.liveCardio.session") {
        self.defaults = defaults; self.key = key
    }
    public func load() -> PhoneLiveCardioSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PhoneLiveCardioSession.self, from: data)
    }
    public func save(_ session: PhoneLiveCardioSession?) {
        if let session, let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Owns inactivity for the one live iPhone cardio session. Lives on `AppModel`, never
/// in a view, so a parked/minimized/backgrounded workout still reaches its terminal state
/// at the original policy deadline. Time is always injected.
@MainActor
public final class PhoneCardioInactivityCoordinator {
    /// Evidence counts as GPS progress only for steps at least this large.
    public static let minimumDistanceStep: Double = 10

    public private(set) var session: PhoneLiveCardioSession?
    private let store: PhoneLiveCardioStoring
    public weak var actions: PhoneCardioLifecycleActions?
    private var finalizing = false

    public init(store: PhoneLiveCardioStoring = InMemoryPhoneLiveCardioStore(),
                actions: PhoneCardioLifecycleActions? = nil) {
        self.store = store
        self.actions = actions
        self.session = store.load()
    }

    // MARK: Lifecycle

    /// Registers a new live session (a prior finalized/absent one is replaced).
    public func attach(session new: PhoneLiveCardioSession) {
        var s = new
        s.lastUserActionAt = s.lastUserActionAt ?? s.start
        session = s
        persist()
    }

    /// Clears a session that reached its terminal state (finalized or user-ended/cancelled).
    public func detachTerminalSession() {
        session = nil
        persist()
    }

    public var autoEndedReceipt: PhoneLiveCardioSession.TerminalReceipt? {
        guard let r = session?.receipt, r.finalized else { return nil }
        return r
    }

    // MARK: Evidence

    /// Applies one evidence event. Passive events and events that arrive after the
    /// running deadline has already passed (reconcile first) are ignored.
    public func recordEvidence(_ evidence: CardioEvidenceEvent, at: Date) {
        guard var s = session, s.receipt == nil, !s.isPaused else { return }
        if case .autoPause = CardioInactivityPolicy.decide(evidence: s.evidence, now: at,
                                                           enabled: s.autoPauseEnabled) { return }
        switch evidence {
        case .userAction:
            s.lastUserActionAt = max(s.lastUserActionAt ?? at, at)
        case .distance(let total):
            guard total.isFinite, total >= s.lastCountedDistance + Self.minimumDistanceStep else { return }
            s.lastCountedDistance = total
            s.lastDistanceProgressAt = max(s.lastDistanceProgressAt ?? at, at)
        case .motion:
            s.lastMotionAt = max(s.lastMotionAt ?? at, at)
        case .heartRate(let bpm, let sampleAt, let resting, let maxHR):
            guard CardioInactivityPolicy.isQualifyingHeartRate(
                bpm: bpm, sampleAt: sampleAt, receivedAt: at,
                previousQualifyingAt: s.lastQualifyingHeartRateAt,
                restingHeartRate: resting, maxHeartRate: maxHR) else { return }
            s.lastQualifyingHeartRateAt = sampleAt
        case .passive:
            return
        }
        s.inactivity.lastQualifyingActivityAt = s.evidence.lastQualifyingEvidenceAt
        session = s
        persist()
    }

    /// User paused. Manual pause is never auto-ended.
    public func recordManualPause(at: Date) {
        guard var s = session, s.receipt == nil, !s.isPaused else { return }
        s.inactivity.recordManualPause(at: at)
        session = s; persist()
    }

    /// User resumed (from a manual or automatic pause). Refused once the terminal
    /// deadline has passed; `reconcile` will end the workout instead.
    @discardableResult
    public func recordResume(at: Date) -> Bool {
        guard var s = session, s.receipt == nil, let pausedAt = s.inactivity.pausedAt else { return false }
        if s.inactivity.pauseOrigin == .automatic, s.autoPauseEnabled,
           at >= CardioInactivityPolicy.terminalDeadline(autoPausedAt: pausedAt) { return false }
        s.pausedAccumulated += max(0, at.timeIntervalSince(pausedAt))
        s.inactivity.recordResume(at: at)
        s.lastUserActionAt = at
        session = s; persist()
        return true
    }

    // MARK: Reconcile

    /// Applies any expired deadline at the ORIGINAL deadline time, not `now`.
    /// Safe to call repeatedly: a finalized/in-flight session no-ops.
    public func reconcile(now: Date) async {
        guard !finalizing else { return }
        guard var s = session else { return }
        if let r = s.receipt {
            if !r.finalized { await finalize(r) }
            return
        }
        switch CardioInactivityPolicy.decide(evidence: s.evidence, now: now, enabled: s.autoPauseEnabled) {
        case .continueRunning, .continuePaused:
            return
        case .autoPause(let deadline):
            s.inactivity.recordAutoPause(at: deadline)
            session = s; persist()
            actions?.pauseForInactivity(session: s, at: deadline)
            // The grace period may also have elapsed while suspended.
            await reconcile(now: now)
        case .autoEnd(let deadline):
            s.inactivity.recordAutoEnd(at: deadline)
            let receipt = PhoneLiveCardioSession.TerminalReceipt(endedAt: deadline, reason: .inactivity)
            s.receipt = receipt
            session = s; persist()
            await finalize(receipt)
        }
    }

    private func finalize(_ receipt: PhoneLiveCardioSession.TerminalReceipt) async {
        guard let id = session?.id, !finalizing else { return }
        finalizing = true
        await actions?.finalizePhoneCardio(sessionID: id, endedAt: receipt.endedAt, reason: receipt.reason)
        finalizing = false
        if var s = session, s.id == id {
            s.receipt?.finalized = true
            session = s; persist()
        }
    }

    private func persist() { store.save(session) }
}
