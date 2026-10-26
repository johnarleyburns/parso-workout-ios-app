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

    /// The phone's generated Today strength suggestion (the same plan the Home hero
    /// shows) as a Watch session carrying full per-set prescriptions, so Watch
    /// Suggest matches the phone instead of repeating the previous workout.
    public static func suggestedStrengthSession(from plan: EditablePlan) -> WatchSync.TodayPlan.Session? {
        let exercises = plan.exercises.filter { !$0.sets.isEmpty }
        guard !exercises.isEmpty else { return nil }
        let title = plan.title.isEmpty ? "Strength" : plan.title
        let names = exercises.map(\.name)
        let ladder = exercises[0].sets.map(\.targetReps)
        let prescriptions = exercises.map { exercise in
            PlannedExercisePrescription(
                exerciseName: exercise.name,
                sets: exercise.sets.map { PlannedSetPrescription(
                    targetReps: $0.targetReps,
                    targetWeightKg: $0.targetWeight,
                    targetLoadMode: $0.loadMode == .straight ? nil : $0.loadMode.rawValue,
                    oneRepMaxPercent: $0.oneRepMaxPercent) },
                supersetGroup: exercise.supersetGroup?.raw)
        }
        let payload = WatchPlanPayload(
            title: title,
            strength: .init(exerciseNames: names, repLadder: ladder, prescriptions: prescriptions))
        return .init(id: "today-suggested-strength", kind: .strength, label: title,
                     exerciseNames: names, repLadder: ladder, planPayload: payload)
    }

    /// Coach projection with the generated strength suggestion taking the place of
    /// the coach's thin strength session (or leading the list when it has none).
    public static func todayPlan(from decision: CoachDecision,
                                 suggestedStrength plan: EditablePlan?,
                                 updatedAt: Date = Date()) -> WatchSync.TodayPlan {
        let base = todayPlan(from: decision, updatedAt: updatedAt)
        guard let plan, let suggested = suggestedStrengthSession(from: plan) else { return base }
        var sessions = base.sessions.filter { !$0.isStrength }
        sessions.insert(suggested, at: 0)
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
