import Foundation
import Testing
import CadenceCore
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

    @Test func livePhoneCardioKeepsActivityAndEndedCardioEndsIt() {
        #expect(LiveActivityReconcilePolicy.action(workoutIsActive: false, hasStrengthSession: false,
                                                   hasPhoneCardioSession: true, ownedActivityCount: 1) == .update)
        // Manual end/cancel/auto-end detach or receipt the session: the single endAll fires.
        #expect(LiveActivityReconcilePolicy.action(workoutIsActive: false, hasStrengthSession: false,
                                                   hasPhoneCardioSession: false, ownedActivityCount: 1) == .endAll)
    }

    @Test func phoneCardioContentReflectsPauseDistanceAndLiveness() {
        let start = Date(timeIntervalSince1970: 1_000)
        var session = PhoneLiveCardioSession(type: .run, route: "outdoor", start: start,
                                             sensorProfile: .outdoor, autoPauseEnabled: true)
        #expect(PhoneCardioLiveActivityContent.isLive(session))
        var c = PhoneCardioLiveActivityContent(session: session, now: start.addingTimeInterval(90))
        #expect(c.elapsedSeconds == 90 && !c.isPaused && c.distanceMeters == nil && c.title == "Run")
        session.lastCountedDistance = 1200
        session.inactivity.recordManualPause(at: start.addingTimeInterval(100))
        c = PhoneCardioLiveActivityContent(session: session, now: start.addingTimeInterval(160))
        #expect(c.elapsedSeconds == 100 && c.isPaused && c.distanceMeters == 1200)
        session.receipt = .init(endedAt: start.addingTimeInterval(200), reason: .inactivity)
        #expect(!PhoneCardioLiveActivityContent.isLive(session))
        #expect(!PhoneCardioLiveActivityContent.isLive(nil))
    }
}
