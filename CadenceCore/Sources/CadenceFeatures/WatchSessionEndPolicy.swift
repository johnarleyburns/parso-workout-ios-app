import Foundation
import CadenceCore

/// Transport keys for the additive, versioned strength completion metadata (v2).
public enum StrengthCompletionKey {
    public static let reason = "completion_reason"
    public static let endedAt = "ended_at"
    public static let inactivityDeadline = "inactivity_deadline"
    public static let completionID = "completion_id"
    public static let version = "v"
}

/// Parsed `end_session` completion metadata. Never infers inactivity from a missing field.
public struct StrengthCompletionEnvelope: Equatable, Sendable {
    public let sessionID: UUID
    /// nil for legacy payloads (treated as a user finish).
    public let reason: StrengthEndReason?
    public let endedAt: Date?
    public let inactivityDeadline: Date?
    public let completionID: UUID?
    public let version: Int
    /// Route claimed by the payload (HR transfer identity), when present.
    public let route: WatchStrengthCompletionRoute?

    public init(sessionID: UUID, reason: StrengthEndReason?, endedAt: Date?, inactivityDeadline: Date?,
                completionID: UUID?, version: Int, route: WatchStrengthCompletionRoute? = nil) {
        self.sessionID = sessionID; self.reason = reason; self.endedAt = endedAt
        self.inactivityDeadline = inactivityDeadline; self.completionID = completionID
        self.version = version; self.route = route
    }

    public init(userInfo: [String: Any]) {
        func uuid(_ v: Any?) -> UUID? { (v as? String).flatMap(UUID.init(uuidString:)) }
        func date(_ v: Any?) -> Date? { (v as? Double).map { Date(timeIntervalSince1970: $0) } }
        let sid = uuid(userInfo["session_id"]) ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        var route: WatchStrengthCompletionRoute?
        if let t = uuid(userInfo[WatchStrengthCompletionKey.transferID]),
           let e = uuid(userInfo[WatchStrengthCompletionKey.captureEpoch]) {
            route = WatchStrengthCompletionRoute(sessionID: sid, transferID: t, captureEpoch: e)
        }
        self.init(sessionID: sid,
                  reason: (userInfo[StrengthCompletionKey.reason] as? String).flatMap(StrengthEndReason.init(rawValue:)),
                  endedAt: date(userInfo[StrengthCompletionKey.endedAt]),
                  inactivityDeadline: date(userInfo[StrengthCompletionKey.inactivityDeadline]),
                  completionID: uuid(userInfo[StrengthCompletionKey.completionID]),
                  version: userInfo[StrengthCompletionKey.version] as? Int ?? 1,
                  route: route)
    }

    /// Inactivity completion with every required field present and consistent.
    public var isValidInactivity: Bool {
        guard reason == .inactivity, version >= 2, completionID != nil,
              let endedAt, let inactivityDeadline else { return false }
        return endedAt == inactivityDeadline
    }
}

/// Durable receipt of an applied completion (persisted on `WorkoutSession`).
public struct StrengthCompletionRecord: Equatable, Sendable {
    public let sessionID: UUID
    public let completionID: UUID?
    public let reason: StrengthEndReason?
    public let endedAt: Date
    public init(sessionID: UUID, completionID: UUID?, reason: StrengthEndReason?, endedAt: Date) {
        self.sessionID = sessionID; self.completionID = completionID
        self.reason = reason; self.endedAt = endedAt
    }
}

public enum StrengthCompletionApplyDecision: Equatable, Sendable {
    case apply
    case alreadyApplied
    case rejectStale
    case rejectForeign
}

/// Pure policy for watch-relayed `end_session` messages. Terminal states dominate: a completed
/// session is never re-ended or extended by a later or duplicated message.
public enum WatchSessionEndPolicy {
    public static func decide(incoming: StrengthCompletionEnvelope,
                              persisted: StrengthCompletionRecord?,
                              activeSessionID: UUID?,
                              acceptedWatchRoute: WatchStrengthCompletionRoute?) -> StrengthCompletionApplyDecision {
        let isInactivity = incoming.reason == .inactivity
        if isInactivity, !incoming.isValidInactivity { return .rejectForeign }

        if let persisted, persisted.sessionID == incoming.sessionID {
            if let id = incoming.completionID, id == persisted.completionID { return .alreadyApplied }
            if isInactivity {
                // Never overwrite a user finish or an earlier/newer terminal completion.
                return .rejectStale
            }
        }

        if activeSessionID == incoming.sessionID {
            // Only an authenticated, valid inactivity completion may end the phone's live session.
            guard isInactivity, let route = acceptedWatchRoute,
                  route.sessionID == incoming.sessionID,
                  incoming.route == route else { return .rejectForeign }
        }
        return .apply
    }

    /// Legacy compatibility: a non-authenticated end never applies to the phone-active session.
    public static func shouldApplyEnd(sessionID: UUID, phoneActiveID: UUID?) -> Bool {
        guard let phoneActiveID else { return true }
        return sessionID != phoneActiveID
    }
}
