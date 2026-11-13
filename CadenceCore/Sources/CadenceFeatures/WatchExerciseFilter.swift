import Foundation
import CadenceCore

/// Narrowing choices layered on a Watch muscle-group list: compound/isolation
/// and equipment. `nil` means "Any" for that facet.
public struct WatchExerciseFilter: Equatable, Sendable {
    public var mechanics: Mechanics?
    public var equipment: Equipment?

    public init(mechanics: Mechanics? = nil, equipment: Equipment? = nil) {
        self.mechanics = mechanics
        self.equipment = equipment
    }

    public var isActive: Bool { mechanics != nil || equipment != nil }

    public func apply(to entries: [ExerciseCatalogEntry]) -> [ExerciseCatalogEntry] {
        entries.filter { entry in
            (mechanics == nil || entry.mechanicsValue == mechanics)
                && (equipment == nil || entry.equipmentValue == equipment)
        }
    }

    /// The full equipment roster, so the picker always offers every option
    /// (dumbbell, barbell, ...) regardless of what the current list contains.
    public var availableEquipment: [Equipment] { Equipment.allCases }
}
