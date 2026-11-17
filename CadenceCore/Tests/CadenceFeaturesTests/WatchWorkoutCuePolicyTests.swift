import XCTest
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

final class WatchWorkoutCuePolicyTests: XCTestCase {
    func testStrengthRestCompletionPlaysExactlyThreeDistinctBells() {
        XCTAssertEqual(WatchWorkoutCuePolicy.restCompletionBellOffsets.count, 3)
        XCTAssertEqual(WatchWorkoutCuePolicy.restCompletionBellOffsets, [0, 0.85, 1.70])
    }
}
