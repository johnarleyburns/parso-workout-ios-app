import Foundation
import CadenceCore

/// Presentation rules for the ready Watch suggestion card. Pure values: the
/// view renders them and the workout changes only through
/// `WatchStrengthFlowModel.addSuggestedExercise` after the native Add confirm.
public enum WatchSuggestedExerciseCard {
    public static let unavailableMessage = "This exercise is no longer available. Refresh and try again."

    /// The catalog entry for the suggestion, matched by canonical name (the
    /// candidate was built from that name). Nil means Add must stay disabled.
    public static func resolve(_ suggestion: SuggestedWorkoutExercise,
                               in catalog: ExerciseCatalogSnapshot) -> ExerciseCatalogEntry? {
        let key = ExerciseLibrary.dedupKey(suggestion.name)
        return catalog.entries.first { ExerciseLibrary.dedupKey($0.name) == key }
    }

    public static func prescriptionText(_ suggestion: SuggestedWorkoutExercise) -> String {
        let range = suggestion.repRange
        let reps = range.lowerBound == range.upperBound
            ? "\(range.lowerBound)" : "\(range.lowerBound)–\(range.upperBound)"
        return "\(suggestion.plannedSets) sets · \(reps) reps"
    }

    /// Short "why": the primary muscles the movement trains.
    public static func muscleChips(for suggestion: SuggestedWorkoutExercise,
                                   entry: ExerciseCatalogEntry?) -> [String] {
        if let entry, !entry.summaryMuscleGroups.isEmpty {
            return entry.summaryMuscleGroups.map(\.displayName)
        }
        return Array(suggestion.contributions.prefix(3).map(\.muscleID))
    }
}
