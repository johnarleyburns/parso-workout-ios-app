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

/// Primary/secondary muscle roles for a custom exercise created on the watch.
/// Uses the full shared catalog; a muscle holds at most one role.
public struct WatchCustomExerciseMuscleAttribution: Equatable, Sendable {
    public enum Role: Sendable { case primary, secondary }

    public static var availableGroups: [MuscleGroup] { MuscleGroup.canonicalOrder }

    public private(set) var primary: Set<MuscleGroup>
    public private(set) var secondary: Set<MuscleGroup>

    public init(primary: Set<MuscleGroup> = [], secondary: Set<MuscleGroup> = []) {
        self.primary = primary
        self.secondary = secondary.subtracting(primary)
    }

    /// The most recently chosen role wins; the other role loses the group.
    public mutating func select(_ group: MuscleGroup, as role: Role) {
        switch role {
        case .primary: secondary.remove(group); primary.insert(group)
        case .secondary: primary.remove(group); secondary.insert(group)
        }
    }

    /// Tap behavior: tapping a selected chip clears it, otherwise it takes the role.
    public mutating func toggle(_ group: MuscleGroup, as role: Role) {
        switch role {
        case .primary:
            if primary.contains(group) { primary.remove(group) } else { select(group, as: .primary) }
        case .secondary:
            if secondary.contains(group) { secondary.remove(group) } else { select(group, as: .secondary) }
        }
    }

    public func contains(_ group: MuscleGroup, as role: Role) -> Bool {
        role == .primary ? primary.contains(group) : secondary.contains(group)
    }

    public var hasPrimaryMuscle: Bool { !primary.isEmpty }
    public var primaryIDs: [String] { MuscleGroup.sorted(primary).map(\.rawValue) }
    public var secondaryIDs: [String] { MuscleGroup.sorted(secondary).map(\.rawValue) }
}
