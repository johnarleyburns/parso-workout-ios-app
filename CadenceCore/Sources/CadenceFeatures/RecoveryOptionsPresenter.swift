import Foundation
import CadenceCore

/// Small, editable recovery drafts, never the normal hard-workout generator.
public enum RecoveryOptionsPresenter {
    public static let citationIDs = ["schoenfeld2021", "ekelundActivityMortality2016"]

    public static func resistancePlan(excludedKeys: Set<String> = []) -> EditablePlan {
        EditablePlan(title: "Light resistance", warmupMinutes: 3, cooldownMinutes: 0,
                     exercises: ["Bodyweight Squat", "Incline Push-Up"].filter { name in
            guard let template = ExerciseLibrary.template(matching: name) else { return false }
            return SuggestedExerciseFilter.allows(template, keys: excludedKeys)
        }.map {
            EditableExercise(name: $0, sets: [EditableSet(targetReps: 8, targetWeight: nil, loadMode: .bodyweight)],
                             notes: "Target ≥5 RIR (at least 5 reps left). Easy effort only; use a wall or high support for push-ups. Stop if uncomfortable.")
        })
    }

    public static var cardio: [CoachSession] {
        [("walk", "Easy walk"), ("cycle", "Easy cycle")].map { type, title in
            CoachSession(id: "recovery.easy.\(type)", kind: .easyAerobic, title: title,
                         subtitle: "10–15 minutes · relaxed pace, comfortable conversation",
                         durationMinutes: 15, intensity: .easy,
                         trainingLoadTags: ["easy", "recovery"],
                         citationIds: ["ekelundActivityMortality2016"],
                         launchPayload: .cardio(type: type, durationMinutes: 15))
        }
    }
}
