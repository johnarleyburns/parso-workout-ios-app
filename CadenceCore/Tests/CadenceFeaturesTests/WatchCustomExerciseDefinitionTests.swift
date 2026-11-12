import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchCustomExerciseDefinitionTests: XCTestCase {
    func testMuscleGroupPillsMapToStableCategories() {
        let muscles = WatchCustomExerciseDefinition.primaryMuscles(for: [.chest, .biceps])
        XCTAssertEqual(muscles, ["chest", "biceps"])
    }

    func testOneMovementFamilyGetsUsefulCategory() {
        XCTAssertEqual(WatchCustomExerciseDefinition.category(for: [.lats, .biceps]), .pull)
        XCTAssertEqual(WatchCustomExerciseDefinition.category(for: [.quadriceps, .calves]), .legs)
    }

    func testMixedMovementFamiliesRemainOther() {
        XCTAssertEqual(WatchCustomExerciseDefinition.category(for: [.chest, .quadriceps]), .other)
        XCTAssertEqual(WatchCustomExerciseDefinition.category(for: []), .other)
    }

    func testCatalogIsTheExactSharedCanonicalMuscleCatalog() {
        XCTAssertEqual(WatchCustomExerciseMuscleAttribution.availableGroups, MuscleGroup.canonicalOrder)
        XCTAssertEqual(Set(WatchCustomExerciseMuscleAttribution.availableGroups), Set(MuscleGroup.allCases))
        XCTAssertEqual(WatchCustomExerciseMuscleAttribution.availableGroups.count, MuscleGroup.allCases.count)
        for group in MuscleGroup.allCases {
            XCTAssertTrue(WatchCustomExerciseMuscleAttribution.availableGroups.contains(group))
        }
    }

    func testRoleSelectionMakesNewlyChosenRoleWinAndNeverOverlaps() {
        var attribution = WatchCustomExerciseMuscleAttribution(primary: [.chest], secondary: [.triceps])
        attribution.select(.chest, as: .secondary)
        XCTAssertFalse(attribution.primary.contains(.chest))
        XCTAssertTrue(attribution.secondary.contains(.chest))
        XCTAssertTrue(attribution.primary.isDisjoint(with: attribution.secondary))

        attribution.select(.chest, as: .primary)
        XCTAssertTrue(attribution.primary.contains(.chest))
        XCTAssertFalse(attribution.secondary.contains(.chest))
    }

    func testPersistedArraysAreCanonicalAndKeepPrimaryAndSecondarySeparate() {
        let attribution = WatchCustomExerciseMuscleAttribution(
            primary: [.triceps, .chest], secondary: [.shoulders, .triceps])
        XCTAssertEqual(attribution.primaryIDs, ["chest", "triceps"])
        XCTAssertEqual(attribution.secondaryIDs, ["shoulders"])
    }

    func testCategoryUsesPrimaryGroupsOnly() {
        let attribution = WatchCustomExerciseMuscleAttribution(primary: [.chest], secondary: [.quadriceps])
        XCTAssertEqual(WatchCustomExerciseDefinition.category(for: attribution.primary), .push)
    }

    func testPrimaryIsRequired() {
        XCTAssertFalse(WatchCustomExerciseMuscleAttribution(secondary: [.chest]).hasPrimaryMuscle)
        XCTAssertTrue(WatchCustomExerciseMuscleAttribution(primary: [.chest]).hasPrimaryMuscle)
    }
}
