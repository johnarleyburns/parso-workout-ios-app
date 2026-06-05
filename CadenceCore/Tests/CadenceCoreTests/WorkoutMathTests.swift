import XCTest
@testable import CadenceCore

final class WorkoutMathTests: XCTestCase {

    func testEpleyAtSingleRepEqualsWeight() {
        XCTAssertEqual(WorkoutMath.epley1RM(weight: 100, reps: 1), 100, accuracy: 0.0001)
    }

    func testEpleyMultiRep() {
        // 100 * (1 + 5/30) = 116.6667
        XCTAssertEqual(WorkoutMath.epley1RM(weight: 100, reps: 5), 116.6667, accuracy: 0.001)
    }

    func testEpleyZeroOrNegativeRepsIsZero() {
        XCTAssertEqual(WorkoutMath.epley1RM(weight: 100, reps: 0), 0)
        XCTAssertEqual(WorkoutMath.epley1RM(weight: 100, reps: -3), 0)
    }

    func testBrzyckiSingleRep() {
        XCTAssertEqual(WorkoutMath.brzycki1RM(weight: 100, reps: 1), 100, accuracy: 0.0001)
    }

    func testBrzyckiMultiRep() {
        // 100 / (1.0278 - 0.0278*5) = 112.512
        XCTAssertEqual(WorkoutMath.brzycki1RM(weight: 100, reps: 5), 112.512, accuracy: 0.01)
    }

    func testBrzyckiDegenerateHighReps() {
        XCTAssertGreaterThan(WorkoutMath.brzycki1RM(weight: 100, reps: 40), 0)
    }

    func testEstimated1RMDispatch() {
        XCTAssertEqual(WorkoutMath.estimated1RM(weight: 100, reps: 5, formula: .epley),
                       WorkoutMath.epley1RM(weight: 100, reps: 5))
        XCTAssertEqual(WorkoutMath.estimated1RM(weight: 100, reps: 5, formula: .brzycki),
                       WorkoutMath.brzycki1RM(weight: 100, reps: 5))
    }

    func testVolume() {
        XCTAssertEqual(WorkoutMath.volume(weight: 102.5, reps: 5), 512.5, accuracy: 0.0001)
        XCTAssertEqual(WorkoutMath.volume(weight: 100, reps: -1), 0)
    }

    func testUnitConversionRoundTrip() {
        let kg = 102.5
        let lb = WorkoutMath.kgToLb(kg)
        XCTAssertEqual(WorkoutMath.lbToKg(lb), kg, accuracy: 1e-9)
        XCTAssertEqual(lb, 225.97, accuracy: 0.01)
    }

    func testDisplayAndCanonical() {
        XCTAssertEqual(WorkoutMath.display(100, in: .kilograms), 100)
        XCTAssertEqual(WorkoutMath.display(100, in: .pounds), 220.46, accuracy: 0.01)
        XCTAssertEqual(WorkoutMath.canonical(220.462, from: .pounds), 100, accuracy: 0.01)
        XCTAssertEqual(WorkoutMath.canonical(100, from: .kilograms), 100)
    }
}
