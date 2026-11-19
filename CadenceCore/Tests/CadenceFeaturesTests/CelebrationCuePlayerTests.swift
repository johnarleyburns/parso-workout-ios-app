import Testing
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// Pins the testable seam that the app's celebration-firing call sites
/// (SessionView+SetActions, InlineSetEditorView, IntervalCues.completed(),
/// RecordAssessmentView) are wired through `CuePolicy.cue(for:)` instead of
/// calling `Haptics` directly. `CelebrationCuePlayer` is the thin wrapper that
/// makes that policy-consultation step unit-testable without UIKit/AVFoundation.
struct CelebrationCuePlayerTests {
    @Test func offSuppressesPersonalBestCelebrationEntirely() {
        let player = CelebrationCuePlayer(celebrationStyle: .off)
        #expect(player.decide(for: .loggedSet(isPersonalBest: true)) == nil)
    }

    @Test func offSuppressesSetLoggedCelebration() {
        let player = CelebrationCuePlayer(celebrationStyle: .off)
        #expect(player.decide(for: .loggedSet(isPersonalBest: false)) == nil)
    }

    @Test func offSuppressesDayCompletedCelebration() {
        let player = CelebrationCuePlayer(celebrationStyle: .off)
        #expect(player.decide(for: .dayCompleted) == nil)
    }

    @Test func offStillFiresFunctionalRestCue() {
        let player = CelebrationCuePlayer(celebrationStyle: .off)
        #expect(player.decide(for: .restFinished)?.kind == .restDone)
    }

    @Test func quietFiresHapticWithoutSoundForDayCompleted() {
        let player = CelebrationCuePlayer(celebrationStyle: .quiet)
        let decision = player.decide(for: .dayCompleted)
        #expect(decision?.kind == .dayClosed)
        #expect(decision?.playsSound == false, "Quiet should keep the haptic but drop the sound/speech accompaniment")
    }

    @Test func fullFiresHapticAndSoundForDayCompleted() {
        let player = CelebrationCuePlayer(celebrationStyle: .full)
        let decision = player.decide(for: .dayCompleted)
        #expect(decision?.kind == .dayClosed)
        #expect(decision?.playsSound == true)
    }

    @Test func quietStillFiresPersonalBestHaptic() {
        let player = CelebrationCuePlayer(celebrationStyle: .quiet)
        #expect(player.decide(for: .loggedSet(isPersonalBest: true))?.kind == .personalBest)
    }

    @Test func functionalCuesAlwaysFireRegardlessOfCelebrationStyle() {
        for style in CelebrationStyle.allCases {
            let player = CelebrationCuePlayer(celebrationStyle: style)
            #expect(player.decide(for: .restFinished)?.kind == .restDone, "style: \(style)")
            #expect(player.decide(for: .intervalWork)?.kind == .intervalWork, "style: \(style)")
            #expect(player.decide(for: .intervalRest)?.kind == .intervalRest, "style: \(style)")
        }
    }

    @Test func initFromExistingPolicyMatchesConvenienceInit() {
        let policy = CuePolicy(celebrationStyle: .quiet)
        let fromPolicy = CelebrationCuePlayer(policy: policy)
        let fromStyle = CelebrationCuePlayer(celebrationStyle: .quiet)
        #expect(fromPolicy.decide(for: .dayCompleted) == fromStyle.decide(for: .dayCompleted))
    }
}
