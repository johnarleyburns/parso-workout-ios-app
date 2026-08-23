import Foundation
import Observation

public enum WatchHRRejection: String, Codable, Sendable {
    case alreadyActive
    case watchWorkoutActive
    case unavailable
    case unsupported
    case healthPermissionDenied
    case sessionStartFailed
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
    public init(initial: WatchHRConnectionState = .actionRequired(message: "Open Cladiron on your Apple Watch")) { state = initial }
    public func begin(requestID: UUID = UUID(), now: Date = Date()) {
        self.requestID = requestID
        state = .connecting(requestID: requestID, startedAt: now)
    }
    public func acknowledged(now: Date = Date()) {
        if case .connecting(let id, _) = state { state = .waitingForSample(requestID: id, acknowledgedAt: now) }
    }
    @discardableResult public func receive(bpm: Int, requestID: UUID, now: Date = Date()) -> Bool {
        guard bpm > 0, bpm < 300 else { return false }
        switch state {
        case .connecting(let id, _), .waitingForSample(let id, _):
            guard requestID == id else { return false }
            state = .live(requestID: id, bpm: bpm, receivedAt: now); return true
        case .live(let id, _, _):
            guard requestID == id else { return false }
            state = .live(requestID: id, bpm: bpm, receivedAt: now); return true
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

    public func timeout() { state = .timedOut(message: "No live heart rate arrived. Open Cladiron on your Watch and retry.") }
    public func fail(_ message: String) { state = .failed(message: message) }
    public func cancel() {
        requestID = nil
        state = .actionRequired(message: "Apple Watch HR is not connected")
    }
    public var activeRequestID: UUID? {
        requestID
    }
    public func freshBPM(at now: Date = Date()) -> Int? {
        guard case .live(_, let bpm, let receivedAt) = state, now.timeIntervalSince(receivedAt) <= 10 else { return nil }
        return bpm
    }
    public var freshBPM: Int? { freshBPM(at: Date()) }
}
