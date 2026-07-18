import Foundation

/// Guards the phone's live workout against watch-relayed end messages
/// (launch-blockers plan, Phase 1d). The phone's active session ends only by
/// an explicit tap on the phone; a watch `end_session` may finalize any
/// *other* (watch-created) session.
public enum WatchSessionEndPolicy {
    public static func shouldApplyEnd(sessionID: UUID, phoneActiveID: UUID?) -> Bool {
        guard let phoneActiveID else { return true }
        return sessionID != phoneActiveID
    }
}
