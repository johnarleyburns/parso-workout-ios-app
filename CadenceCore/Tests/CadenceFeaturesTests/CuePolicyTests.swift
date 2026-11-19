import Testing
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct CuePolicyTests {
    @Test func personalBestReplacesSetCue() {
        let policy = CuePolicy()
        #expect(policy.cue(for: .loggedSet(isPersonalBest: true)) == .personalBest)
        #expect(policy.cue(for: .loggedSet(isPersonalBest: false)) == .setLogged)
    }

    @Test func quietKeepsHapticCuesButOffSuppressesCelebrations() {
        #expect(CuePolicy(celebrationStyle: .quiet).cue(for: .dayCompleted) == .dayClosed)
        #expect(CuePolicy(celebrationStyle: .off).cue(for: .dayCompleted) == nil)
        #expect(CuePolicy(celebrationStyle: .off).cue(for: .restFinished) == .restDone)
    }

    @Test func restEndingOnlyFiresForFinalThreeSeconds() {
        let policy = CuePolicy()
        #expect(policy.cue(for: .rest(secondsRemaining: 4)) == nil)
        #expect(policy.cue(for: .rest(secondsRemaining: 3)) == .restEnding)
    }
}
