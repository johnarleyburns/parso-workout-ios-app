import Foundation
import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

struct ExerciseBrowseFilterPolicyTests {
    @Test func equipmentFirstBrowsePreservesEquipmentWhenGroupChanges() {
        #expect(!ExerciseBrowseFilterPolicy.resetsEquipmentOnGroupChange(mode: .byEquipment))
    }

    @Test func muscleFirstBrowseResetsEquipmentWhenGroupChanges() {
        #expect(ExerciseBrowseFilterPolicy.resetsEquipmentOnGroupChange(mode: .byMuscleGroup))
    }
}

struct ExerciseBrowseFilterStateTests {
    private func entry(_ name: String, groups: Set<MuscleGroup>, equipment: Equipment?) -> ExerciseCatalogEntry {
        ExerciseCatalogEntry(id: UUID(), name: name, primaryMuscleGroups: Array(groups),
                             trainedMuscleGroups: groups, equipmentValue: equipment)
    }

    private var results: [ExerciseCatalogEntry] {
        [entry("Hip Thrust", groups: [.glutes], equipment: .barbell),
         entry("Barbell Squat", groups: [.chest, .glutes], equipment: .barbell),
         entry("Dumbbell Glute Bridge", groups: [.glutes], equipment: .dumbbell),
         entry("Barbell Curl", groups: [.biceps], equipment: .barbell)]
    }

    @Test func textSearchWithBarbellAndGlutesReturnsOnlyMatchingExercises() {
        let state = ExerciseBrowseFilterState(mode: .byEquipment, group: .glutes, equipment: .barbell)
        #expect(state.filterSearchResults(results).map(\.name) == ["Hip Thrust", "Barbell Squat"])
    }

    @Test func searchAllExercisesClearsFacetConstraintsButNotQuery() {
        var state = ExerciseBrowseFilterState(tab: .browse, group: .glutes, equipment: .barbell)
        state.clearFacets()
        #expect(!state.hasFacets)
        #expect(state.filterSearchResults(results).count == results.count)
    }

    @Test func equipmentFirstGroupNarrowingPreservesEquipment() {
        #expect(!ExerciseBrowseFilterPolicy.resetsEquipmentOnGroupChange(mode: .byEquipment))
    }

    @Test func clearAllReturnsToUnfilteredBrowse() {
        var state = ExerciseBrowseFilterState(tab: .popular, mode: .byEquipment, group: .glutes, equipment: .barbell)
        state.clearAll()
        #expect(state.tab == .browse)
        #expect(state.group == nil)
        #expect(state.equipment == nil)
    }

    @Test func noMatchesForFiltersOffersClearFilters() {
        let state = ExerciseBrowseFilterState(group: .calves, equipment: .barbell)
        #expect(state.filterSearchResults(results).isEmpty)
        #expect(state.hasFacets, "empty result with facets must offer Clear filters")
    }

    @Test func singleFacetStillAppliesAfterClearingOtherChip() {
        var state = ExerciseBrowseFilterState(group: .glutes, equipment: .barbell)
        state.group = nil
        #expect(state.filterSearchResults(results).count == 3)
    }

    @Test func filterControlsExposeSelectedAccessibilityStateAndMinimumHitArea() {
        #expect(ExerciseFilterAccessibility.minimumHitTarget >= 44)
        #expect(ExerciseFilterAccessibility.selectedValue(isSelected: true))
        #expect(ExerciseFilterAccessibility.removeChipLabel("Barbell") == "Remove Barbell filter")
    }
}
