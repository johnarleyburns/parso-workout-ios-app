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

    func testVolume() {
        XCTAssertEqual(WorkoutMath.volume(weight: 102.5, reps: 5), 512.5, accuracy: 0.0001)
    }
}
