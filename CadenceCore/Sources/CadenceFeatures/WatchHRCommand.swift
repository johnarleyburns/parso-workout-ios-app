import Foundation

/// Versioned phone-to-Watch control message for a live-HR workout session.
///
/// Stop commands are sent both interactively and through WatchConnectivity's
/// guaranteed background queue. `issuedAt` makes that duplicate idempotent and
/// prevents an old queued stop from ending a newer session.
public struct WatchHRCommand: Equatable, Sendable {
    public enum Action: String, Sendable { case start = "start_workout", stop = "stop_workout" }

    public static let issuedAtKey = "watchHRCommandIssuedAt"

    public let action: Action
    public let requestID: UUID?
    public let workoutType: String?
    public let issuedAt: TimeInterval

    public init(action: Action, requestID: UUID?, workoutType: String? = nil, issuedAt: TimeInterval) {
        self.action = action
        self.requestID = requestID
        self.workoutType = workoutType
        self.issuedAt = issuedAt
    }

    public init?(payload: [String: Any]) {
        guard let rawAction = payload[WatchSync.Key.command] as? String,
              let action = Action(rawValue: rawAction),
              let issuedAt = payload[Self.issuedAtKey] as? Double else { return nil }
        let requestID = (payload["requestID"] as? String).flatMap(UUID.init(uuidString:))
        if action == .start, requestID == nil { return nil }
        self.init(action: action,
                  requestID: requestID,
                  workoutType: payload["type"] as? String,
                  issuedAt: issuedAt)
    }

    public var payload: [String: Any] {
        var result: [String: Any] = [
            WatchSync.Key.command: action.rawValue,
            Self.issuedAtKey: issuedAt,
        ]
        if let requestID { result["requestID"] = requestID.uuidString }
        if let workoutType { result["type"] = workoutType }
        return result
    }

    public func isNewer(than lastApplied: TimeInterval?) -> Bool {
        guard let lastApplied else { return true }
        return issuedAt > lastApplied
    }

    /// Produces a timestamp that remains strictly increasing even if several
    /// commands are emitted in one clock tick or the wall clock moves backward.
    public static func nextIssuedAt(now: TimeInterval, after previous: TimeInterval?) -> TimeInterval {
        guard let previous, now <= previous else { return now }
        return previous.nextUp
    }
}
