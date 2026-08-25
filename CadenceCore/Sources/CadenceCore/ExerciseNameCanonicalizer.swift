import Foundation

/// Name-level heuristics: turning a raw exercise name into a matching key, and
/// guessing a category when no template exists to copy facets from.
///
/// These used to live on `MuscleCatalog` and `BodyPart` respectively. Both types
/// were deleted when `MuscleGroup` became the single training dimension (DB++
/// adoption, phase 6), so the string heuristics — which never had anything to do
/// with the muscle vocabulary — moved here unchanged.
public enum ExerciseNameCanonicalizer {
    /// Canonicalize an exercise name for matching purposes. Strips equipment,
    /// grip, and laterality qualifiers so "Double Kettlebell Snatch" and
    /// "Snatch" resolve to the same matching key. Does NOT mutate stored
    /// exerciseName — this is a matching key only.
    public static func canonicalName(_ name: String) -> String {
        let lower = name.lowercased()

        let qualifiers: [String] = [
            "double kettlebell", "single kettlebell",
            "double dumbbell", "single dumbbell",
            "double", "single",
            "kettlebell", "dumbbell", "barbell",
            "standing", "seated",
            "alternate", "alternating",
            "machine", "cable",
            "smith",
            "- pronated grip", "- supinated grip",
            "pronated grip", "supinated grip",
            "banded",
        ]

        var result = lower
        for qualifier in qualifiers {
            result = result.replacingOccurrences(of: qualifier, with: "")
        }

        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.trimmingCharacters(in: .whitespaces)

        return result.isEmpty ? lower : result
    }
}

public extension ExerciseCategory {
    /// Guess a category from a raw exercise name using common fitness naming
    /// conventions observed across `ExerciseLibrary` and free-exercise-db++.
    static func guess(fromName name: String) -> ExerciseCategory? {
        let lower = name.lowercased()
        if lower.contains("press") || lower.contains("push") || lower.contains("extension")
            || lower.contains("fly") || lower.contains("raise") || lower.contains("overhead") {
            return .push
        }
        if lower.contains("curl") || lower.contains("row") || lower.contains("pulldown")
            || lower.contains("pull") || lower.contains("snatch") || lower.contains("clean") {
            return .pull
        }
        if lower.contains("squat") || lower.contains("deadlift") || lower.contains("lunge")
            || lower.contains("leg") || lower.contains("calf") || lower.contains("step")
            || lower.contains("hip thrust") || lower.contains("glute") {
            return .legs
        }
        if lower.contains("crunch") || lower.contains("abs") || lower.contains("core")
            || lower.contains("plank") || lower.contains("sit-up") || lower.contains("torso")
            || lower.contains("russian twist") || lower.contains("leg raise") {
            return .core
        }
        return nil
    }
}
