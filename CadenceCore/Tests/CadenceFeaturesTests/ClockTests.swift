import Foundation
import Testing
import CadenceFeatures
import CadenceWorkoutFeatures

struct ClockTests {
    @Test func fixedClockReturnsPinnedInstant() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let clock = Clock.fixed(t)
        #expect(clock.now() == t)
        #expect(clock.now() == t)
    }

    @Test func liveClockAdvances() {
        let clock = Clock.live
        let a = clock.now()
        #expect(clock.now().timeIntervalSince(a) >= 0)
    }
}
