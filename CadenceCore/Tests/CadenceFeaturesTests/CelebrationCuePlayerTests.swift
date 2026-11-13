import XCTest
import CadenceFeatures

/// Pins the testable seam that the app's celebration-firing call sites
/// (SessionView+SetActions, InlineSetEditorView, IntervalCues.completed(),
/// RecordAssessmentView) are wired through `CuePolicy.cue(for:)` instead of
/// calling `Haptics` directly. `CelebrationCuePlayer` is the thin wrapper that
/// makes that policy-consultation step unit-testable without UIKit/AVFoundation.
final class CelebrationCuePlayerTests: XCTestCase {
    func testOffSuppressesPersonalBestCelebrationEntirely() {
        let player = CelebrationCuePlayer(celebrationStyle: .off)
        XCTAssertNil(player.decide(for: .loggedSet(isPersonalBest: true)))
    }

    func testOffSuppressesSetLoggedCelebration() {
        let player = CelebrationCuePlayer(celebrationStyle: .off)
        XCTAssertNil(player.decide(for: .loggedSet(isPersonalBest: false)))
    }

    func testOffSuppressesDayCompletedCelebration() {
        let player = CelebrationCuePlayer(celebrationStyle: .off)
        XCTAssertNil(player.decide(for: .dayCompleted))
    }

    func testOffStillFiresFunctionalRestCue() {
        let player = CelebrationCuePlayer(celebrationStyle: .off)
        XCTAssertEqual(player.decide(for: .restFinished)?.kind, .restDone)
    }

    func testQuietFiresHapticWithoutSoundForDayCompleted() {
        let player = CelebrationCuePlayer(celebrationStyle: .quiet)
        let decision = player.decide(for: .dayCompleted)
        XCTAssertEqual(decision?.kind, .dayClosed)
        XCTAssertEqual(decision?.playsSound, false, "Quiet should keep the haptic but drop the sound/speech accompaniment")
    }

    func testFullFiresHapticAndSoundForDayCompleted() {
        let player = CelebrationCuePlayer(celebrationStyle: .full)
        let decision = player.decide(for: .dayCompleted)
        XCTAssertEqual(decision?.kind, .dayClosed)
        XCTAssertEqual(decision?.playsSound, true)
    }

    func testQuietStillFiresPersonalBestHaptic() {
        let player = CelebrationCuePlayer(celebrationStyle: .quiet)
        XCTAssertEqual(player.decide(for: .loggedSet(isPersonalBest: true))?.kind, .personalBest)
    }

    func testFunctionalCuesAlwaysFireRegardlessOfCelebrationStyle() {
        for style in CelebrationStyle.allCases {
            let player = CelebrationCuePlayer(celebrationStyle: style)
            XCTAssertEqual(player.decide(for: .restFinished)?.kind, .restDone, "style: \(style)")
            XCTAssertEqual(player.decide(for: .intervalWork)?.kind, .intervalWork, "style: \(style)")
            XCTAssertEqual(player.decide(for: .intervalRest)?.kind, .intervalRest, "style: \(style)")
        }
    }

    func testInitFromExistingPolicyMatchesConvenienceInit() {
        let policy = CuePolicy(celebrationStyle: .quiet)
        let fromPolicy = CelebrationCuePlayer(policy: policy)
        let fromStyle = CelebrationCuePlayer(celebrationStyle: .quiet)
        XCTAssertEqual(fromPolicy.decide(for: .dayCompleted), fromStyle.decide(for: .dayCompleted))
    }
}
