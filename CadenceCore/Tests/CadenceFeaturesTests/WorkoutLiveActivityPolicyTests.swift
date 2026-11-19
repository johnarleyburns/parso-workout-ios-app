import Foundation
import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WorkoutLiveActivityPolicyTests {
    @Test func noActiveWorkoutEndsEveryActivity() {
        // Regression (issue #74): an orphaned activity must be ended on launch
        // when no workout is running.
        #expect(WorkoutLiveActivityPolicy.reconciliation(workoutIsActive: false) == .endAllActivities)
    }

    @Test func activeWorkoutKeepsActivity() {
        #expect(WorkoutLiveActivityPolicy.reconciliation(workoutIsActive: true) == .runActivity)
    }

    @Test func staleDateIsBoundedSoUnrefreshedActivityExpires() {
        let now = Date(timeIntervalSince1970: 1_000)
        let stale = WorkoutLiveActivityPolicy.staleDate(from: now)
        #expect(stale.timeIntervalSince(now) == WorkoutLiveActivityPolicy.staleAfter)
        #expect(WorkoutLiveActivityPolicy.staleAfter <= 15 * 60)
    }
}
