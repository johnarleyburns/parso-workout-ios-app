import Foundation

/// One phone-owned Watch-HR connection. Identified by an immutable
/// (`phoneSessionID`, `requestID`) pair, never by mutable UI state.
public struct WatchHRConnectionIdentity: Equatable, Codable, Sendable {
    public let phoneSessionID: UUID
    public let requestID: UUID
    public init(phoneSessionID: UUID, requestID: UUID) {
        self.phoneSessionID = phoneSessionID
        self.requestID = requestID
    }
    /// Opaque, redacted form for diagnostics and UI.
    public var redacted: String { "\(phoneSessionID.uuidString.prefix(4))/\(requestID.uuidString.prefix(4))" }
}

public enum WatchHRReconcileReason: String, Equatable, Sendable {
    case initialWaitElapsed, reachabilityChanged, appActivated, userRequested, requestMismatch
}

public enum WatchHRFailureReason: String, Equatable, Sendable {
    case noResponse, requestMismatch, watchOnlyWorkoutActive, watchNotRunningWorkout
    case orphanedWatchSession, protocolMismatch, retriesExhausted
}

public enum WatchHRLinkState: Equatable, Sendable {
    case notRequested
    case startingWatchWorkout(WatchHRConnectionIdentity)
    case awaitingWatchAdoption
    case awaitingFirstSample
    case live(lastSampleAt: Date)
    case reconciling(WatchHRReconcileReason)
    case recoverableFailure(WatchHRFailureReason, retryAvailable: Bool)
    case ending
    case ended
}

extension WatchHRLinkState {
    /// Identifier-free name for logs and diagnostics.
    public var label: String {
        switch self {
        case .notRequested: "notRequested"
        case .startingWatchWorkout: "startingWatchWorkout"
        case .awaitingWatchAdoption: "awaitingWatchAdoption"
        case .awaitingFirstSample: "awaitingFirstSample"
        case .live: "live"
        case .reconciling(let r): "reconciling(\(r.rawValue))"
        case .recoverableFailure(let r, _): "recoverableFailure(\(r.rawValue))"
        case .ending: "ending"
        case .ended: "ended"
        }
    }
}

/// The single safe action a state report resolves to.
public enum WatchHRReconcileDecision: Equatable, Sendable {
    case accept                       // Watch owns the matching session
    case redeliverStart               // Watch has nothing adopted yet; resend idempotently
    case stopOrphan(requestID: UUID)  // Watch holds an older phone-owned session
    case conflict(WatchHRFailureReason)
}

public struct WatchHRDiagnostics: Equatable, Sendable {
    public let state: WatchHRLinkState
    public let attemptCount: Int
    public let redactedIdentity: String?
    public let lastTransition: String
    public let lastRealSampleAge: TimeInterval?
    public let lastFailure: WatchHRFailureReason?
}

/// Deterministic (clock passed in) state machine for the handshake.
public struct WatchHRConnection: Sendable {
    public static let initialWait: TimeInterval = 15
    public static let maxAttempts = 5
    public static let maxBackoff: TimeInterval = 120

    public private(set) var identity: WatchHRConnectionIdentity?
    public private(set) var state: WatchHRLinkState = .notRequested
    public private(set) var attempts = 0
    public private(set) var lastFailure: WatchHRFailureReason?
    public private(set) var lastTransition = "notRequested"
    private var lastSampleAt: Date?
    private var nextQueryAt: Date?

    public init() {}

    public mutating func start(_ identity: WatchHRConnectionIdentity, now: Date) {
        self.identity = identity
        attempts = 0; lastFailure = nil; lastSampleAt = nil
        nextQueryAt = now.addingTimeInterval(Self.initialWait)
        move(.startingWatchWorkout(identity))
    }

    public mutating func watchLaunched() {
        if case .startingWatchWorkout = state { move(.awaitingWatchAdoption) }
    }

    /// Watch acknowledged adopting exactly these identifiers.
    @discardableResult
    public mutating func adopted(_ adopted: WatchHRConnectionIdentity) -> Bool {
        guard adopted == identity else { return false }
        switch state {
        case .startingWatchWorkout, .awaitingWatchAdoption, .reconciling, .recoverableFailure:
            move(.awaitingFirstSample)
        default: break
        }
        return true
    }

    /// Accepts a sample only for the current identity; a mismatch is explicit.
    public enum SampleOutcome: Equatable, Sendable { case accepted, rejectedMismatch, rejectedInactive }

    public mutating func receiveSample(requestID: UUID, at: Date) -> SampleOutcome {
        guard let identity else { return .rejectedInactive }
        switch state {
        case .notRequested, .ending, .ended: return .rejectedInactive
        default: break
        }
        guard requestID == identity.requestID else {
            lastFailure = .requestMismatch
            return .rejectedMismatch
        }
        lastSampleAt = at
        attempts = 0
        move(.live(lastSampleAt: at))
        return .accepted
    }

    public func displayedSampleAge(now: Date) -> TimeInterval? {
        lastSampleAt.map { now.timeIntervalSince($0) }
    }

    /// A live state older than the stale window is not "live".
    public func isLive(now: Date) -> Bool {
        guard case .live(let at) = state else { return false }
        return now.timeIntervalSince(at) <= WatchHRRelay.staleAfter
    }

    /// Time-driven: returns a reason when a state query should be sent now.
    /// Exponential backoff, bounded attempts; never continuous polling.
    public mutating func tick(now: Date) -> WatchHRReconcileReason? {
        switch state {
        case .startingWatchWorkout, .awaitingWatchAdoption, .awaitingFirstSample, .reconciling: break
        case .live where !isLive(now: now): break
        default: return nil
        }
        guard let due = nextQueryAt, now >= due else { return nil }
        return beginAttempt(.initialWaitElapsed, now: now)
    }

    /// Reachability / activation: prompt attempt, still bounded.
    public mutating func reachabilityOrActivation(_ reason: WatchHRReconcileReason, now: Date) -> WatchHRReconcileReason? {
        switch state {
        case .startingWatchWorkout, .awaitingWatchAdoption, .awaitingFirstSample, .reconciling, .recoverableFailure:
            return beginAttempt(reason, now: now)
        case .live where !isLive(now: now):
            return beginAttempt(reason, now: now)
        default: return nil
        }
    }

    /// The explicit user "Reconnect Apple Watch HR" action resets the budget.
    public mutating func userReconnect(now: Date) -> WatchHRReconcileReason? {
        guard identity != nil, state != .ended, state != .ending else { return nil }
        attempts = 0
        return beginAttempt(.userRequested, now: now)
    }

    private mutating func beginAttempt(_ reason: WatchHRReconcileReason, now: Date) -> WatchHRReconcileReason? {
        guard attempts < Self.maxAttempts else {
            nextQueryAt = nil
            fail(.retriesExhausted, retry: true)
            return nil
        }
        attempts += 1
        let backoff = min(Self.initialWait * pow(2, Double(attempts)), Self.maxBackoff)
        nextQueryAt = now.addingTimeInterval(backoff)
        move(.reconciling(reason))
        return reason
    }

    /// Pure comparison of the Watch's report with the phone's expectation.
    public static func decide(report: WatchHRStateReport, expecting identity: WatchHRConnectionIdentity,
                              expectedType: String = "strength") -> WatchHRReconcileDecision {
        guard report.protocolVersion >= 2 else { return .conflict(.protocolMismatch) }
        guard report.isWorkoutActive else { return .redeliverStart }
        if report.adoptedRequestID == identity.requestID {
            guard report.adoptedPhoneSessionID == nil || report.adoptedPhoneSessionID == identity.phoneSessionID,
                  report.workoutType == nil || report.workoutType == expectedType else {
                return .conflict(.requestMismatch)
            }
            return report.healthKitRunning ? .accept : .conflict(.watchNotRunningWorkout)
        }
        if let other = report.adoptedRequestID { return .stopOrphan(requestID: other) }
        // Active, nothing adopted: ours only if it is a phone launch awaiting its command.
        if report.awaitingAdoption, report.workoutType == nil || report.workoutType == expectedType {
            return .redeliverStart
        }
        return .conflict(.watchOnlyWorkoutActive)
    }

    public mutating func apply(_ decision: WatchHRReconcileDecision) {
        switch decision {
        case .accept:
            if case .live = state { break }
            move(.awaitingFirstSample)
        case .redeliverStart: move(.awaitingWatchAdoption)
        case .stopOrphan: fail(.orphanedWatchSession, retry: true)
        case .conflict(let reason): fail(reason, retry: reason != .watchOnlyWorkoutActive)
        }
    }

    public mutating func end() { move(.ending); move(.ended); nextQueryAt = nil }

    public func diagnostics(now: Date) -> WatchHRDiagnostics {
        WatchHRDiagnostics(state: state, attemptCount: attempts, redactedIdentity: identity?.redacted,
                           lastTransition: lastTransition, lastRealSampleAge: displayedSampleAge(now: now),
                           lastFailure: lastFailure)
    }

    private mutating func fail(_ reason: WatchHRFailureReason, retry: Bool) {
        lastFailure = reason
        move(.recoverableFailure(reason, retryAvailable: retry))
    }

    private mutating func move(_ new: WatchHRLinkState) {
        lastTransition = "\(state.label) -> \(new.label)"
        state = new
    }
}
