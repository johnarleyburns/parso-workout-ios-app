import Testing
@testable import CadenceCore

/// Field test 2026-08-18 issue 2. `BW` must mean "this movement is bodyweight",
/// never "we could not find a weight" (decision D4).
struct ExerciseLoadingTests {
    @Test func catalogBodyweightMovementsAreDetected() {
        for name in ["Push-Up", "Pull-Up", "Dip"] {
            #expect(ExerciseLoading.isBodyweight(named: name), "\(name) is a bodyweight movement")
        }
    }

    @Test func loadedMovementsAreNotBodyweight() {
        // The field-test regression, asserted by name.
        #expect(!ExerciseLoading.isBodyweight(named: "Standing Dumbbell Upright Row"),
                       "Standing Dumbbell Upright Row is loaded — it must never render as BW")
        for name in ["Bench Press", "Barbell Curl", "Back Squat"] {
            #expect(!ExerciseLoading.isBodyweight(named: name), "\(name) is a loaded movement")
        }
    }

    @Test func timeHoldsAreDetected() {
        #expect(ExerciseLoading.isTimeHold(named: "Plank"))
        #expect(ExerciseLoading.isTimeHold(named: "Wall Sit"))
        #expect(!ExerciseLoading.isTimeHold(named: "Bench Press"))
    }
}
