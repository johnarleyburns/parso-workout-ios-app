import Foundation
import CadenceCore

/// Decides which exercise-browse filters survive a change of the muscle-group filter.
public enum ExerciseBrowseFilterPolicy {
    public enum Mode: Sendable { case byMuscleGroup, byEquipment }

    /// Equipment narrows the list when browsing by muscle group, so it resets with the
    /// group. When browsing by equipment, equipment is the primary filter and the
    /// group only narrows it, so the chosen equipment must be preserved.
    public static func resetsEquipmentOnGroupChange(mode: Mode) -> Bool {
        mode == .byMuscleGroup
    }
}

/// Pure selection/result behavior behind the Find / Add picker filters.
///
/// Search contract: a non-empty query searches the full catalog, narrowed only by
/// the active group / equipment facets. The Recents and Popular scopes are never
/// retained as a search constraint.
public struct ExerciseBrowseFilterState: Equatable, Sendable {
    public enum Tab: Sendable, Equatable { case browse, recents, popular }
    public typealias Mode = ExerciseBrowseFilterPolicy.Mode

    public var tab: Tab = .browse
    public var mode: Mode = .byMuscleGroup
    public var group: MuscleGroup?
    public var equipment: Equipment?

    public init(tab: Tab = .browse, mode: Mode = .byMuscleGroup,
                group: MuscleGroup? = nil, equipment: Equipment? = nil) {
        self.tab = tab
        self.mode = mode
        self.group = group
        self.equipment = equipment
    }

    public var hasFacets: Bool { group != nil || equipment != nil }

    /// Returns to the unfiltered Browse state.
    public mutating func clearAll() { tab = .browse; group = nil; equipment = nil }

    /// "Search all exercises": drops facet constraints only (the query is not owned here).
    public mutating func clearFacets() { group = nil; equipment = nil }

    /// Facet match for a search result. Without a query the facet index already
    /// narrows browse results, so the facets only gate search output.
    public func matches(_ entry: ExerciseCatalogEntry, queryIsActive: Bool) -> Bool {
        guard queryIsActive else { return true }
        if let group, !entry.trainedMuscleGroups.contains(group) { return false }
        if let equipment, entry.equipmentValue != equipment { return false }
        return true
    }

    public func filterSearchResults(_ results: [ExerciseCatalogEntry]) -> [ExerciseCatalogEntry] {
        hasFacets ? results.filter { matches($0, queryIsActive: true) } : results
    }
}

/// Accessibility contract for Find filter / scope controls.
public enum ExerciseFilterAccessibility {
    /// Minimum tappable height and width, in points.
    public static let minimumHitTarget: Double = 44

    public static func removeChipLabel(_ constraint: String) -> String { "Remove \(constraint) filter" }
    public static func selectedValue(isSelected: Bool) -> Bool { isSelected }
}
