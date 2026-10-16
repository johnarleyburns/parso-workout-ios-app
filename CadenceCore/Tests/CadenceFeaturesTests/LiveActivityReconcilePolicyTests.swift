import Foundation
import Testing
@testable import CadenceFeatures

@Suite struct LiveActivityReconcilePolicyTests {
    @Test func finishedWorkoutEndsOrphanedActivity() {
        #expect(LiveActivityReconcilePolicy.action(workoutIsActive: false, hasStrengthSession: false,
                                                   ownedActivityCount: 1) == .endAll)
    }

    @Test func activeWorkoutKeepsActivity() {
        #expect(LiveActivityReconcilePolicy.action(workoutIsActive: true, hasStrengthSession: true,
                                                   ownedActivityCount: 1) == .update)
    }

    @Test func activeNonStrengthWorkoutEndsActivity() {
        #expect(LiveActivityReconcilePolicy.action(workoutIsActive: true, hasStrengthSession: false,
                                                   ownedActivityCount: 2) == .endAll)
    }

    @Test func nothingToDoWhenNoActivityAndNoWorkout() {
        #expect(LiveActivityReconcilePolicy.action(workoutIsActive: false, hasStrengthSession: false,
                                                   ownedActivityCount: 0) == nil)
    }

    @Test func staleDateIsBounded() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(LiveActivityReconcilePolicy.staleDate(from: now).timeIntervalSince(now)
                == LiveActivityReconcilePolicy.staleAfter)
    }
}
