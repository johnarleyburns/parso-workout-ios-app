import Foundation
import Observation

public enum WatchHRRejection: String, Codable, Sendable {
    case alreadyActive
    case watchWorkoutActive
    case unavailable
    case unsupported
    case healthPermissionDenied
    case sessionStartFailed

    /// What the phone tells the user when the Watch turns a request down.
    public var userMessage: String {
        switch self {
        case .alreadyActive:
            return "Your Apple Watch is still finishing an earlier heart-rate session. Tap Check for Live HR again."
        case .watchWorkoutActive:
            return "A workout is already running in Cladiron on your Apple Watch. End it there, then tap Check for Live HR."
        case .unavailable:
            return "Heart rate isn’t available from your Apple Watch right now. Tap Check for Live HR to try again."
        case .unsupported:
            return "This Apple Watch can’t stream heart rate to your iPhone."
        case .healthPermissionDenied:
            // The one case the user must act on the Watch: watchOS shows the
            // Health permission sheet only there.
            return "Cladiron doesn’t have Health access on your Apple Watch yet. Open Cladiron on the Watch once to allow it, then tap Check for Live HR."
        case .sessionStartFailed:
            return "Your Apple Watch couldn’t start the workout. Tap Check for Live HR to try again."
        }
    }
}

public struct WatchHRReply: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let accepted: Bool
    public let rejection: WatchHRRejection?

    public init(requestID: UUID, accepted: Bool, rejection: WatchHRRejection? = nil) {
        self.requestID = requestID
        self.accepted = accepted
        self.rejection = rejection
    }
}

public enum WatchHRConnectionState: Equatable, Sendable {
    case unavailable(reason: String)
    case actionRequired(message: String)
    /// Cladiron was not running on the Watch; the phone asked HealthKit to open
    /// it (`HKHealthStore.startWatchApp`) and is waiting for it to launch.
    case launchingWatchApp(requestID: UUID, startedAt: Date)
    case connecting(requestID: UUID, startedAt: Date)
    case waitingForSample(requestID: UUID, acknowledgedAt: Date)
    case live(requestID: UUID, bpm: Int, receivedAt: Date)
    case timedOut(message: String)
    case failed(message: String)
}

@MainActor @Observable
public final class WatchHRRelay {
    public private(set) var state: WatchHRConnectionState
    /// Kept independently from `state` so a timeout still retains enough
    /// identity to stop the Watch session that may be running remotely.
    private var requestID: UUID?

    /// The Watch resends its last reading every `WatchHRRelaySchedule
    /// .heartbeatInterval` when no new one arrives, so heart rate is stale only
    /// after three heartbeats have been missed.
    nonisolated public static let staleAfter: TimeInterval = 3 * WatchHRRelaySchedule.heartbeatInterval

    public init(initial: WatchHRConnectionState = .actionRequired(message: "Tap Check for Live HR to connect your Apple Watch")) { state = initial }
    /// Starts a request. `launchingWatchApp` when the phone is opening
    /// Cladiron on the Watch first; otherwise the Watch app is already running.
    public func begin(requestID: UUID = UUID(), launchingWatchApp: Bool = false, now: Date = Date()) {
        self.requestID = requestID
        state = launchingWatchApp
            ? .launchingWatchApp(requestID: requestID, startedAt: now)
            : .connecting(requestID: requestID, startedAt: now)
    }
    /// HealthKit reports the Watch app launched; it now has the workout and
    /// is connecting back to the phone.
    public func watchAppLaunched(now: Date = Date()) {
        if case .launchingWatchApp(let id, _) = state { state = .connecting(requestID: id, startedAt: now) }
    }
    /// The Watch accepted the request. Its reply can beat HealthKit's launch
    /// callback, so this also completes a launch in progress.
    public func acknowledged(now: Date = Date()) {
        switch state {
        case .launchingWatchApp(let id, _), .connecting(let id, _):
            state = .waitingForSample(requestID: id, acknowledgedAt: now)
        default:
            break
        }
    }
    @discardableResult public func receive(bpm: Int, requestID: UUID, now: Date = Date()) -> Bool {
        guard bpm > 0, bpm < 300 else { return false }
        switch state {
        case .launchingWatchApp(let id, _), .connecting(let id, _), .waitingForSample(let id, _):
            guard requestID == id else { return false }
            state = .live(requestID: id, bpm: bpm, receivedAt: now); return true
        case .live(let id, _, _):
            guard requestID == id else { return false }
            state = .live(requestID: id, bpm: bpm, receivedAt: now); return true
        case .timedOut:
            // A timeout means the transport went quiet, not that the Watch
            // workout was proven to have ended. Keep the request identity so a
            // later sample can recover the phone UI after a transient
            // WatchConnectivity/Apple Fitness interruption.
            guard requestID == self.requestID else { return false }
            state = .live(requestID: requestID, bpm: bpm, receivedAt: now); return true
        default: return false
        }
    }
    /// Whether a rejected `start_workout` should be followed by an automatic
    /// stop-then-retry. Only `.alreadyActive` means the watch still owns a
    /// (probably stale) session the phone can tear down and start fresh; the
    /// other rejections are user/permission problems a retry would just hammer.
    public static func shouldRetryAfterStop(rejection: WatchHRRejection?) -> Bool {
        rejection == .alreadyActive
    }

    public func timeout() {
        state = .timedOut(message: "No heart rate arrived from your Apple Watch. Check that it’s on your wrist and unlocked, then tap Check for Live HR.")
    }
    public func fail(_ message: String) { state = .failed(message: message) }
    public func cancel() {
        requestID = nil
        state = .actionRequired(message: "Apple Watch HR is not connected")
    }
    public var activeRequestID: UUID? {
        requestID
    }
    public func freshBPM(at now: Date = Date()) -> Int? {
        guard case .live(_, let bpm, let receivedAt) = state,
              now.timeIntervalSince(receivedAt) <= Self.staleAfter else { return nil }
        return bpm
    }
    public var freshBPM: Int? { freshBPM(at: Date()) }
}
