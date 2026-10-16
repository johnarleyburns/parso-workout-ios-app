import Foundation
import XCTest
@testable import CadenceFeatures

final class WorkoutLiveActivityPolicyTests: XCTestCase {
    func testNoActiveWorkoutEndsEveryActivity() {
        // Regression (issue #74): an orphaned activity must be ended on launch
        // when no workout is running.
        XCTAssertEqual(WorkoutLiveActivityPolicy.reconciliation(workoutIsActive: false), .endAllActivities)
    }

    func testActiveWorkoutKeepsActivity() {
        XCTAssertEqual(WorkoutLiveActivityPolicy.reconciliation(workoutIsActive: true), .runActivity)
    }

    func testStaleDateIsBoundedSoUnrefreshedActivityExpires() {
        let now = Date(timeIntervalSince1970: 1_000)
        let stale = WorkoutLiveActivityPolicy.staleDate(from: now)
        XCTAssertEqual(stale.timeIntervalSince(now), WorkoutLiveActivityPolicy.staleAfter)
        XCTAssertLessThanOrEqual(WorkoutLiveActivityPolicy.staleAfter, 15 * 60)
    }
}
