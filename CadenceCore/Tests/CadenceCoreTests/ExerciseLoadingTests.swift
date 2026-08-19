import XCTest
@testable import CadenceCore

/// Field test 2026-08-18 issue 2. `BW` must mean "this movement is bodyweight",
/// never "we could not find a weight" (decision D4).
final class ExerciseLoadingTests: XCTestCase {
    func testCatalogBodyweightMovementsAreDetected() {
        for name in ["Push-Up", "Pull-Up", "Dip"] {
            XCTAssertTrue(ExerciseLoading.isBodyweight(named: name), "\(name) is a bodyweight movement")
        }
    }

    func testLoadedMovementsAreNotBodyweight() {
        // The field-test regression, asserted by name.
        XCTAssertFalse(ExerciseLoading.isBodyweight(named: "Standing Dumbbell Upright Row"),
                       "Standing Dumbbell Upright Row is loaded — it must never render as BW")
        for name in ["Bench Press", "Barbell Curl", "Back Squat"] {
            XCTAssertFalse(ExerciseLoading.isBodyweight(named: name), "\(name) is a loaded movement")
        }
    }

    func testTimeHoldsAreDetected() {
        XCTAssertTrue(ExerciseLoading.isTimeHold(named: "Plank"))
        XCTAssertTrue(ExerciseLoading.isTimeHold(named: "Wall Sit"))
        XCTAssertFalse(ExerciseLoading.isTimeHold(named: "Bench Press"))
    }
}
