import CadenceCore

/// Converts the watch's muscle-group pills into the facets stored on a custom
/// exercise. This keeps creation useful to history/coverage without bringing the
/// phone's full muscle editor to the wrist.
public enum WatchCustomExerciseDefinition {
    /// The muscle ids to store, in canonical order. Since the wrist now picks the
    /// same `MuscleGroup` values the rest of the app counts volume in, this is a
    /// straight canonical-order projection — no coarse-part expansion table.
    public static func primaryMuscles(for groups: Set<MuscleGroup>) -> [String] {
        MuscleGroup.sorted(groups).map(\.rawValue)
    }

    /// The movement-split category for the chosen groups, or `.other` when they
    /// span more than one split (a custom "chest + legs" movement is neither).
    public static func category(for groups: Set<MuscleGroup>) -> ExerciseCategory {
        let categories = Set(groups.map(category(forGroup:)))
        return categories.count == 1 ? (categories.first ?? .other) : .other
    }

    private static func category(forGroup group: MuscleGroup) -> ExerciseCategory {
        switch group {
        case .chest, .shoulders, .triceps, .rotatorCuff: return .push
        case .lats, .middleBack, .traps, .biceps, .forearms: return .pull
        case .quadriceps, .hamstrings, .glutes, .calves, .adductors, .abductors, .tibialis:
            return .legs
        case .abdominals, .lowerBack, .hipFlexors: return .core
        case .neck: return .other
        }
    }
}
