import Foundation
import CadenceCore

/// The first-frame representation of a strength recommendation.  Both Home's
/// hero and the planned-workouts affordance use this value, which prevents a
/// compact coach fallback from advertising a different workout than Start opens.
public enum TodayStartupPresentation {
    public static func hero(plan: TodaySuggestedPlanPayload?, coachFallback: TodayHero?,
                            reason: String?) -> TodayHero? {
        guard let plan else { return coachFallback }
        return TodayHero(
            kind: .suggested,
            title: plan.title,
            exercises: plan.exercises.map { exercise in
                let reps = exercise.sets.map(\.targetReps)
                let detail: String
                if let first = reps.first {
                    let last = reps.last ?? first
                    detail = first == last ? "\(exercise.sets.count) × \(first)" : "\(exercise.sets.count) × \(first)–\(last)"
                } else {
                    detail = ""
                }
                return TodayHero.Line(name: exercise.name, detail: detail)
            },
            reason: reason,
            citationIDs: SuggestedWorkoutPresenter.citationIDs)
    }

    /// A fully launchable, conservative local plan for a genuine first-launch
    /// cache miss.  It deliberately uses no history, HealthKit, SwiftData, or
    /// network state.  When personalized facts arrive, the replacement gate
    /// asks before changing this visible plan.
    public static func immediateFallback(style: SuggestedWorkoutStyle,
                                         warmupMinutes: Int, cooldownMinutes: Int)
    -> TodaySuggestedPlanPayload {
        let names: [String]
        switch style {
        case .bodyweight:
            names = ["Bodyweight Squat", "Push-Up", "Glute Bridge", "Reverse Lunge", "Plank"]
        case .powerlifting:
            names = ["Back Squat", "Bench Press", "Deadlift", "Barbell Row", "Plank"]
        case .olympic:
            names = ["Front Squat", "Overhead Press", "Romanian Deadlift", "Barbell Row", "Plank"]
        case .strongman:
            names = ["Goblet Squat", "Overhead Press", "Romanian Deadlift", "Farmer Carry", "Plank"]
        case .fitness, .personalized:
            names = ["Goblet Squat", "Dumbbell Bench Press", "Dumbbell Row", "Romanian Deadlift", "Split Squat", "Plank"]
        }
        let reps = style == .powerlifting ? 5 : 8
        return TodaySuggestedPlanPayload(EditablePlan(
            title: String(localized: "Starter strength workout", bundle: .module),
            warmupMinutes: warmupMinutes,
            cooldownMinutes: cooldownMinutes,
            exercises: names.map {
                EditableExercise(name: $0,
                                 sets: (0..<3).map { _ in EditableSet(targetReps: reps, targetWeight: nil, loadMode: .straight) },
                                 notes: "")
            }))
    }
}
