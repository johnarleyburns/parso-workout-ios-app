import XCTest
@testable import CadenceFeatures
import CadenceCore

final class ExerciseBrowseFilterPolicyTests: XCTestCase {
    func testEquipmentFirstBrowsePreservesEquipmentWhenGroupChanges() {
        XCTAssertFalse(ExerciseBrowseFilterPolicy.resetsEquipmentOnGroupChange(mode: .byEquipment))
    }

    func testMuscleFirstBrowseResetsEquipmentWhenGroupChanges() {
        XCTAssertTrue(ExerciseBrowseFilterPolicy.resetsEquipmentOnGroupChange(mode: .byMuscleGroup))
    }
}

final class ExerciseBrowseFilterStateTests: XCTestCase {
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

    func testTextSearchWithBarbellAndGlutesReturnsOnlyMatchingExercises() {
        let state = ExerciseBrowseFilterState(mode: .byEquipment, group: .glutes, equipment: .barbell)
        XCTAssertEqual(state.filterSearchResults(results).map(\.name), ["Hip Thrust", "Barbell Squat"])
    }

    func testSearchAllExercisesClearsFacetConstraintsButNotQuery() {
        var state = ExerciseBrowseFilterState(tab: .browse, group: .glutes, equipment: .barbell)
        state.clearFacets()
        XCTAssertFalse(state.hasFacets)
        XCTAssertEqual(state.filterSearchResults(results).count, results.count)
    }

    func testEquipmentFirstGroupNarrowingPreservesEquipment() {
        XCTAssertFalse(ExerciseBrowseFilterPolicy.resetsEquipmentOnGroupChange(mode: .byEquipment))
    }

    func testClearAllReturnsToUnfilteredBrowse() {
        var state = ExerciseBrowseFilterState(tab: .popular, mode: .byEquipment, group: .glutes, equipment: .barbell)
        state.clearAll()
        XCTAssertEqual(state.tab, .browse)
        XCTAssertNil(state.group)
        XCTAssertNil(state.equipment)
    }

    func testNoMatchesForFiltersOffersClearFilters() {
        let state = ExerciseBrowseFilterState(group: .calves, equipment: .barbell)
        XCTAssertTrue(state.filterSearchResults(results).isEmpty)
        XCTAssertTrue(state.hasFacets, "empty result with facets must offer Clear filters")
    }

    func testSingleFacetStillAppliesAfterClearingOtherChip() {
        var state = ExerciseBrowseFilterState(group: .glutes, equipment: .barbell)
        state.group = nil
        XCTAssertEqual(state.filterSearchResults(results).count, 3)
    }

    func testFilterControlsExposeSelectedAccessibilityStateAndMinimumHitArea() {
        XCTAssertGreaterThanOrEqual(ExerciseFilterAccessibility.minimumHitTarget, 44)
        XCTAssertTrue(ExerciseFilterAccessibility.selectedValue(isSelected: true))
        XCTAssertEqual(ExerciseFilterAccessibility.removeChipLabel("Barbell"), "Remove Barbell filter")
    }
}
