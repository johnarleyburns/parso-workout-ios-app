import Testing
import CadenceFeatures
import CadenceWorkoutFeatures

struct LiveHeartRateDisplayTests {
    @Test func noSample() {
        let d = LiveHeartRateDisplay(bpm: nil)
        #expect(d.valueText == "--")
        #expect(!d.hasSample)
    }

    @Test func activeSample() {
        #expect(LiveHeartRateDisplay(bpm: 118).valueText == "118")
    }

    @Test func fractionalRounds() {
        #expect(LiveHeartRateDisplay(bpm: 117.5).valueText == "118")
        #expect(LiveHeartRateDisplay(bpm: 117.4).valueText == "117")
    }

    @Test func nonPositiveOrNonFiniteIsNoSample() {
        #expect(!LiveHeartRateDisplay(bpm: 0).hasSample)
        #expect(!LiveHeartRateDisplay(bpm: .nan).hasSample)
    }
}
