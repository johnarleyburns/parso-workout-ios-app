import Foundation

/// Watch Today: the phone's synced plan as separate, deliberately startable choices.
/// Pure presentation; the Watch never creates recommendations itself.
public enum WatchTodayRecommendations {
    public struct Row: Equatable, Sendable, Identifiable {
        public enum Modality: String, Equatable, Sendable { case strength, cardio }
        public let modality: Modality
        public let session: WatchSync.TodayPlan.Session
        /// True for the second row when both modalities are planned (companion/optional work).
        public let isAlsoPlanned: Bool
        public var id: String { session.id }
        public var accessibilityIdentifier: String { "watch.todayRecommendation.\(modality.rawValue).start" }
    }

    public enum StartDecision: Equatable, Sendable {
        case launch(Row)
        /// Several recommendations: the user must pick one from Today.
        case choose
        case none
    }

    /// At most two rows: first strength, then first cardio. Rest sessions are excluded.
    public static func rows(for plan: WatchSync.TodayPlan?) -> [Row] {
        guard let sessions = plan?.sessions else { return [] }
        let strength = sessions.first(where: { $0.kind == .strength })
        let cardio = sessions.first(where: { $0.kind == .cardio })
        var rows: [Row] = []
        if let strength { rows.append(Row(modality: .strength, session: strength, isAlsoPlanned: false)) }
        if let cardio { rows.append(Row(modality: .cardio, session: cardio, isAlsoPlanned: strength != nil)) }
        return rows
    }

    /// Action Button / Smart Stack "Today's Plan": never silently picks one of two.
    public static func startDecision(for plan: WatchSync.TodayPlan?) -> StartDecision {
        let rows = rows(for: plan)
        switch rows.count {
        case 0: return .none
        case 1: return .launch(rows[0])
        default: return .choose
        }
    }

    /// Resume outranks recommendations.
    public static func visibleRows(for plan: WatchSync.TodayPlan?, hasResume: Bool) -> [Row] {
        hasResume ? [] : rows(for: plan)
    }
}
