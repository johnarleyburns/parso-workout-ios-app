import Foundation
import CadenceCore

/// Projects the phone's Today coach suggestion into the Watch "today" shape so the
/// Watch Today hero shows the same suggested workout as the phone (issue #50).
/// The suggestion is advisory: it never replaces the user's schedule (NFR-8).
public enum CoachWatchTodayBridge {
    public static func todayPlan(from decision: CoachDecision, updatedAt: Date = Date()) -> WatchSync.TodayPlan {
        let candidates = decision.todayPlannedRecommendations.isEmpty
            ? [decision.primary] : decision.todayPlannedRecommendations
        var seen = Set<String>()
        let sessions = candidates.compactMap { session -> WatchSync.TodayPlan.Session? in
            guard seen.insert(session.id).inserted else { return nil }
            return watchSession(from: session)
        }
        return WatchSync.TodayPlan(sessions: sessions, updatedAt: updatedAt)
    }

    static func watchSession(from session: CoachSession) -> WatchSync.TodayPlan.Session? {
        switch session.launchPayload {
        case .strengthPlan:
            let exercises = session.exercises ?? []
            return .init(id: session.id, kind: .strength, label: session.title,
                         exerciseNames: exercises.map(\.name),
                         repLadder: exercises.first?.repLadder ?? [])
        case let .cardio(type, minutes):
            return .init(id: session.id, kind: .cardio, label: session.title,
                         cardioType: type, durationMinutes: minutes ?? session.durationMinutes)
        case .rest:
            return .init(id: session.id, kind: .rest, label: session.title)
        case .recovery, .assessment:
            return nil
        }
    }
}
