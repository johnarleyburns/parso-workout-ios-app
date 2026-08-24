import Foundation

/// The eight body parts surfaced on Home's "body parts this week" coverage tile
/// (feedback batch 3). Distinct from the fine-grained `MuscleCatalog`: this is a
/// coarse, user-facing grouping the user named — with "shoulders" in place of the
/// originally-listed "neck" (no neck movements exist; shoulders are trained often).
public enum BodyPart: String, CaseIterable, Sendable, Identifiable, Codable {
    case legs, back, chest, shoulders, biceps, triceps, calves, abs

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .legs: return "Legs"
        case .back: return "Back"
        case .chest: return "Chest"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .calves: return "Calves"
        case .abs: return "Abs"
        }
    }

    /// Maps a `MuscleGroup` to its coarse body part, if any. Forearms have no
    /// coarse bucket and deliberately return nil, exactly as before.
    ///
    /// Transitional: this rollup exists only so the coach optimizer and the rule
    /// engine keep their `BodyPart` dimension while weekly volume moves onto
    /// `MuscleGroup`. Both it and `BodyPart` are deleted in phase 6.
    public static func part(forGroup group: MuscleGroup) -> BodyPart? {
        switch group {
        case .chest: return .chest
        case .lats, .middleBack, .lowerBack, .traps, .neck: return .back
        case .shoulders, .rotatorCuff: return .shoulders
        case .biceps: return .biceps
        case .triceps: return .triceps
        case .calves, .tibialis: return .calves
        case .abdominals: return .abs
        case .quadriceps, .hamstrings, .glutes, .adductors, .abductors, .hipFlexors:
            return .legs
        case .forearms: return nil
        }
    }

    /// Resolves any historical or canonical muscle string to its coarse part.
    public static func part(forMuscleID id: String) -> BodyPart? {
        MuscleGroup.canonical(id).flatMap(part(forGroup:))
    }

    /// The body parts hit by one exercise, given its muscle ids (primary + secondary).
    public static func parts(forMuscleIDs ids: [String]) -> Set<BodyPart> {
        Set(ids.compactMap(part(forMuscleID:)))
    }

    /// Coverage across a week's exercises: each element is one exercise's muscle
    /// ids (primary + secondary). Returns the parts hit and the parts missing
    /// (missing in canonical `allCases` order, for a stable display).
    public static func coverage(forMuscleLists lists: [[String]]) -> (hit: Set<BodyPart>, missing: [BodyPart]) {
        var hit = Set<BodyPart>()
        for ids in lists { hit.formUnion(parts(forMuscleIDs: ids)) }
        let missing = allCases.filter { !hit.contains($0) }
        return (hit, missing)
    }

    /// Body parts implied by an exercise category. Used as a fallback when
    /// primaryMuscles is empty but the category is known.
    public static func parts(forCategory cat: ExerciseCategory) -> Set<BodyPart> {
        switch cat {
        case .push: return [.chest, .shoulders, .triceps]
        case .pull: return [.back, .biceps]
        case .legs: return [.legs, .calves]
        case .core: return [.abs]
        case .cardio, .plyometrics, .other: return []
        }
    }

    /// Default primary muscle IDs for an exercise category. Used when creating
    /// a custom exercise where no template exists but a category is provided.
    public static func defaultMuscles(forCategory cat: ExerciseCategory) -> [String] {
        MuscleGroup.defaults(forCategory: cat).map(\.rawValue)
    }

    /// Guess an ExerciseCategory from a raw name. Forwards to
    /// `ExerciseCategory.guess(fromName:)`, which is where it lives now.
    public static func guessCategory(from name: String) -> ExerciseCategory? {
        ExerciseCategory.guess(fromName: name)
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
