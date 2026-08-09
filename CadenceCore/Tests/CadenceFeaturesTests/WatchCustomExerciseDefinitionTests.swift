import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchCustomExerciseDefinitionTests: XCTestCase {
    func testBodyPartPillsMapToStableMuscleFacets() {
        let muscles = WatchCustomExerciseDefinition.primaryMuscles(for: [.chest, .biceps])
        XCTAssertEqual(muscles, ["chest", "biceps"])
    }

    func testOneMovementFamilyGetsUsefulCategory() {
        XCTAssertEqual(WatchCustomExerciseDefinition.category(for: [.back, .biceps]), .pull)
        XCTAssertEqual(WatchCustomExerciseDefinition.category(for: [.legs, .calves]), .legs)
    }

    func testMixedMovementFamiliesRemainOther() {
        XCTAssertEqual(WatchCustomExerciseDefinition.category(for: [.chest, .legs]), .other)
        XCTAssertEqual(WatchCustomExerciseDefinition.category(for: []), .other)
    }
}
