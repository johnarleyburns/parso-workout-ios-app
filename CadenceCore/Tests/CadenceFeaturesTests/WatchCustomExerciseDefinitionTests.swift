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
}
