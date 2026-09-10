import Foundation
import CadenceCore

/// Projects a self-authored unified plan into the legacy-compatible Watch
/// "today" shape while carrying the rich versioned payload alongside it.
///
/// The Watch currently executes one strength or one cardio session at a time.
/// Mobility, instruction-only, and mixed sessions remain in the unified plan
/// and are intentionally not mislabeled as executable Watch sessions.
public enum ManualPlanWatchBridge {
    public static func todayPlan(
        from plan: Plan,
        date: Date,
        calendar: Calendar = .current,
        exerciseNameByKey: [String: String] = [:],
        athlete: AthleteExecutionSnapshot = .init()
    ) -> WatchSync.TodayPlan {
        guard let weekday = Weekday(from: date, calendar: calendar),
              let day = plan.weeks.first?.days.first(where: { $0.weekday == weekday }) else {
            return WatchSync.TodayPlan(updatedAt: plan.updatedAt)
        }

        let sessions = day.sessions.compactMap { session -> WatchSync.TodayPlan.Session? in
            guard session.executionBoundary.canProjectToWatch else {
                return nil
            }
            let snapshot = PlanSessionSnapshot(session: session,
                                               exerciseNameByKey: exerciseNameByKey)
            let strength = snapshot.strengthItems
            let cardio = snapshot.items.compactMap { item -> CardioItemSnapshot? in
                guard case let .cardio(value) = item else { return nil }
                return value
            }
            guard !strength.isEmpty || !cardio.isEmpty else {
                return nil
            }

            let payload = try? WatchPlanPayload.make(from: snapshot, athlete: athlete)
            let names = strength.map(\.exerciseName)
            let ladder = strength.first?.sets.map(\.targetReps) ?? []
            let firstCardio = cardio.first
            let kind: WatchSync.TodayPlan.Session.Kind = strength.isEmpty ? .cardio : .strength

            return WatchSync.TodayPlan.Session(
                id: session.id.uuidString,
                kind: kind,
                label: session.title,
                exerciseNames: names,
                repLadder: ladder,
                cardioType: firstCardio?.kind,
                durationMinutes: firstCardio?.durationSeconds.map { max(1, Int(ceil(Double($0) / 60)) ) },
                zone: firstCardio?.targetZone,
                planPayload: payload)
        }

        return WatchSync.TodayPlan(sessions: sessions, updatedAt: plan.updatedAt)
    }
}
