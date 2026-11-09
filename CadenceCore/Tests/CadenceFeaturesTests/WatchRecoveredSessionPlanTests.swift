import Testing
@testable import CadenceFeatures

@Suite struct WatchRecoveredSessionPlanTests {
    let id = "7C9E6679-7425-40DE-944B-E07FC1F90AE7"

    @Test func runningPhoneWorkoutIsReadoptedWithIdentity() {
        let plan = WatchRecoveredSessionPlan(state: .running, persistedMonitoring: false, persistedPhoneRequestID: id)
        #expect(plan.action == .adopt)
        #expect(plan.isActive)
        #expect(plan.phoneRequestID == id)
        #expect(WatchPhoneWorkoutPresentation.shouldShow(isActive: plan.isActive, phoneRequestID: plan.phoneRequestID))
    }

    @Test func pausedSessionIsAlsoAdopted() {
        #expect(WatchRecoveredSessionPlan(state: .paused, persistedMonitoring: false, persistedPhoneRequestID: id).action == .adopt)
    }

    @Test func endedSessionIsNeverResurrected() {
        let plan = WatchRecoveredSessionPlan(state: .ended, persistedMonitoring: false, persistedPhoneRequestID: id)
        #expect(plan.action == .discardEnded)
        #expect(!plan.isActive && plan.phoneRequestID == nil)
    }

    @Test func stoppedSessionIsEndedNotAdopted() {
        let plan = WatchRecoveredSessionPlan(state: .stopped, persistedMonitoring: false, persistedPhoneRequestID: id)
        #expect(plan.action == .endStopped)
        #expect(!plan.isActive && plan.phoneRequestID == nil)
    }

    @Test func monitoringAndMalformedIdentityAreNotPhoneOwned() {
        let monitoring = WatchRecoveredSessionPlan(state: .running, persistedMonitoring: true, persistedPhoneRequestID: id)
        #expect(monitoring.isMonitoring && !monitoring.isActive && monitoring.phoneRequestID == nil)
        let bad = WatchRecoveredSessionPlan(state: .running, persistedMonitoring: false, persistedPhoneRequestID: "junk")
        #expect(bad.isActive && bad.phoneRequestID == nil)
    }
}
