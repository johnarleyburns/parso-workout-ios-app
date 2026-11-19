import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct StrengthPauseProvenanceTests {
    @Test func userPauseResume() {
        var p = StrengthPauseProvenance()
        let paused = p.userPause(.userControl)
        #expect(paused)
        #expect(p.origin == .userControl)
        let echoPause = p.healthKitTransition(to: .paused)
        #expect(echoPause == .none)   // echo of our own pause
        #expect(p.origin == .userControl)
        let cantResume = p.healthKitTransition(to: .running)
        #expect(cantResume == .none)  // platform can't resume a user pause
        #expect(p.origin == .userControl)
        p.userResume()
        #expect(p.origin == nil)
    }


    @Test func nonUserOriginCannotBeSetAsUserPause() {
        var p = StrengthPauseProvenance()
        let hkExternal = p.userPause(.healthKitExternal)
        #expect(!hkExternal)
        let recovery = p.userPause(.recovery)
        #expect(!recovery)
        #expect(p.origin == nil)
    }

    @Test func externalPausedIsRecordedOnceAndDistinctCopy() {
        var p = StrengthPauseProvenance()
        let first = p.healthKitTransition(to: .paused)
        #expect(first == .pause)
        let repeated = p.healthKitTransition(to: .paused)
        #expect(repeated == .none)   // repeated callback
        #expect(p.origin == .healthKitExternal)
        #expect(p.statusCopy!.contains("not by you"))
        let resumed = p.healthKitTransition(to: .running)
        #expect(resumed == .resume)
        #expect(p.origin == nil)
        let repeatedResume = p.healthKitTransition(to: .running)
        #expect(repeatedResume == .none)  // repeated
    }

    @Test func recoveredPausedNeedsExplicitResume() {
        var p = StrengthPauseProvenance()
        p.recoveredPaused()
        #expect(p.origin == .recovery)
        #expect(p.statusCopy!.contains("Restored"))
        p.userResume()
        #expect(p.origin == nil)
    }

    @Test func terminalClears() {
        var p = StrengthPauseProvenance()
        _ = p.userPause(.userControl)
        _ = p.healthKitTransition(to: .terminal)
        #expect(p.origin == nil)
        #expect(p.statusCopy == nil)
    }
}
