import Foundation

/// Anything the exercise picker's equipment sub-filter can classify: the muscle
/// groups it trains and its equipment type. Both the SwiftData `Exercise` and
/// lightweight test doubles conform.
public protocol EquipmentClassifiable {
    var trainedMuscleGroups: Set<MuscleGroup> { get }
    var equipmentValue: Equipment? { get }
}

/// A precomputed group → exercises / group → equipment index (built once from the
/// loaded catalog) so the picker's **equipment sub-filter** — a second chip row
/// under the muscle-group row — is an O(1) dictionary lookup plus an O(m) narrow,
/// never an O(catalog) scan per render. Also indexes equipment → exercises so the
/// Browse tab can browse by equipment first.
public struct ExerciseFacetIndex<T: EquipmentClassifiable> {
    /// Exercises training each muscle group, preserving the input order.
    public let byGroup: [MuscleGroup: [T]]
    /// Equipment types present for each muscle group, in canonical order.
    public let equipmentByGroup: [MuscleGroup: [Equipment]]
    /// Exercises grouped by equipment type, preserving input order.
    public let byEquipment: [Equipment: [T]]
    /// Muscle groups that have exercises of each equipment type.
    public let groupsByEquipment: [Equipment: [MuscleGroup]]

    public init(_ items: [T]) {
        var groups: [MuscleGroup: [T]] = [:]
        var equip: [Equipment: [T]] = [:]
        for item in items {
            for group in item.trainedMuscleGroups { groups[group, default: []].append(item) }
            if let eq = item.equipmentValue { equip[eq, default: []].append(item) }
        }
        var equipment: [MuscleGroup: [Equipment]] = [:]
        for (group, list) in groups {
            equipment[group] = Self.equipmentPresent(in: list)
        }
        var groupsForEq: [Equipment: [MuscleGroup]] = [:]
        for (eq, list) in equip {
            groupsForEq[eq] = MuscleGroup.canonicalOrder.filter { g in
                list.contains { $0.trainedMuscleGroups.contains(g) }
            }
        }
        self.byGroup = groups
        self.equipmentByGroup = equipment
        self.byEquipment = equip
        self.groupsByEquipment = groupsForEq
    }

    /// Exercises training `group`, optionally narrowed to a single equipment type.
    public func exercises(for group: MuscleGroup, equipment: Equipment? = nil) -> [T] {
        let base = byGroup[group] ?? []
        guard let equipment else { return base }
        return base.filter { $0.equipmentValue == equipment }
    }

    /// Equipment types available for `group` (deduped, canonical order). Empty when
    /// the group is unknown or has no equipment-tagged movements.
    public func equipment(for group: MuscleGroup) -> [Equipment] {
        equipmentByGroup[group] ?? []
    }

    /// All exercises of a given equipment type, unfiltered by muscle group.
    public func exercises(forEquipment eq: Equipment, group: MuscleGroup? = nil) -> [T] {
        let base = byEquipment[eq] ?? []
        guard let group else { return base }
        return base.filter { $0.trainedMuscleGroups.contains(group) }
    }

    /// Muscle groups that have exercises of the given equipment type.
    public func muscleGroups(forEquipment eq: Equipment) -> [MuscleGroup] {
        groupsByEquipment[eq] ?? []
    }

    /// The distinct equipment types among `items`, in canonical `Equipment.allCases`
    /// order. Untagged (`nil`) equipment is ignored.
    public static func equipmentPresent(in items: [T]) -> [Equipment] {
        let present = Set(items.compactMap { $0.equipmentValue })
        return Equipment.allCases.filter { present.contains($0) }
    }
}

extension Exercise: EquipmentClassifiable {}
