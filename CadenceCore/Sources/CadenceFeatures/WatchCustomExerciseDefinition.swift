import CadenceCore

/// Converts the watch's coarse body-part pills into the facets stored on a
/// custom exercise. This keeps creation useful to history/coverage without
/// bringing the phone's full muscle editor to the wrist.
public enum WatchCustomExerciseDefinition {
    public static func primaryMuscles(for bodyParts: Set<BodyPart>) -> [String] {
        BodyPart.allCases.flatMap { part -> [String] in
            guard bodyParts.contains(part) else { return [] }
            switch part {
            case .legs: return ["quads", "hamstrings", "glutes"]
            case .back: return ["lats", "traps", "rhomboids", "lower-back"]
            case .chest: return ["chest"]
            case .shoulders: return ["delts"]
            case .biceps: return ["biceps"]
            case .triceps: return ["triceps"]
            case .calves: return ["calves"]
            case .abs: return ["abs", "obliques"]
            }
        }
    }

    public static func category(for bodyParts: Set<BodyPart>) -> ExerciseCategory {
        let categories = Set(bodyParts.map { part -> ExerciseCategory in
            switch part {
            case .chest, .shoulders, .triceps: return .push
            case .back, .biceps: return .pull
            case .legs, .calves: return .legs
            case .abs: return .core
            }
        })
        return categories.count == 1 ? (categories.first ?? .other) : .other
    }
}
