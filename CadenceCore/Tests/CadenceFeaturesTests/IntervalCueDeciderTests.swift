import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

struct IntervalCueDeciderTests {

    @Test func firesWarningOncePerWorkPhase() {
        var d = IntervalCueDecider()
        // 30s left in work phase 3 → warning fires once.
        #expect(d.cues(phaseKind: .work, currentPhaseID: 3, phaseRemaining: 30, isPaused: false, isComplete: false) == [.warning])
        // Same phase, still 30 → no repeat.
        #expect(d.cues(phaseKind: .work, currentPhaseID: 3, phaseRemaining: 30, isPaused: false, isComplete: false) == [])
    }

    @Test func warningRearmsForNewPhase() {
        var d = IntervalCueDecider()
        _ = d.cues(phaseKind: .work, currentPhaseID: 3, phaseRemaining: 30, isPaused: false, isComplete: false)
        #expect(d.cues(phaseKind: .work, currentPhaseID: 5, phaseRemaining: 30, isPaused: false, isComplete: false) ==
                       [.phaseTransition(.work), .warning])
    }

    @Test func phaseTransitionCuesWorkAndRestBoundaries() {
        var d = IntervalCueDecider()
        #expect(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 20, isPaused: false, isComplete: false) == [])
        #expect(d.cues(phaseKind: .rest, currentPhaseID: 2, phaseRemaining: 30, isPaused: false, isComplete: false) ==
                       [.phaseTransition(.rest)])
        #expect(d.cues(phaseKind: .work, currentPhaseID: 3, phaseRemaining: 30, isPaused: false, isComplete: false) ==
                       [.phaseTransition(.work), .warning])
    }

    @Test func countdownTicksOnFinalThreeSeconds() {
        var d = IntervalCueDecider()
        #expect(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 3, isPaused: false, isComplete: false) == [.countdownTick])
        #expect(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 2, isPaused: false, isComplete: false) == [.countdownTick])
        #expect(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 2, isPaused: false, isComplete: false) == [])
    }

    @Test func noCuesDuringRestPhase() {
        var d = IntervalCueDecider()
        #expect(d.cues(phaseKind: .rest, currentPhaseID: 2, phaseRemaining: 3, isPaused: false, isComplete: false) == [])
        #expect(d.cues(phaseKind: .rest, currentPhaseID: 2, phaseRemaining: 30, isPaused: false, isComplete: false) == [])
    }

    @Test func noCuesWhenPausedOrComplete() {
        var d = IntervalCueDecider()
        #expect(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 30, isPaused: true, isComplete: false) == [])
        #expect(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 3, isPaused: false, isComplete: true) == [])
    }

    @Test func resetRearmsCountdown() {
        var d = IntervalCueDecider()
        _ = d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 3, isPaused: false, isComplete: false)
        d.reset()
        #expect(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 3, isPaused: false, isComplete: false) == [.countdownTick])
    }

    @Test func getReadyCountdownBeforeWorkInterval() {
        var d = IntervalCueDecider()
        #expect(d.cues(phaseKind: .rest, currentPhaseID: 2, phaseRemaining: 3, nextPhaseKind: .work, isPaused: false, isComplete: false) == [.getReady(3)])
        #expect(d.cues(phaseKind: .rest, currentPhaseID: 2, phaseRemaining: 3, nextPhaseKind: .work, isPaused: false, isComplete: false) == [])
        #expect(d.cues(phaseKind: .rest, currentPhaseID: 2, phaseRemaining: 2, nextPhaseKind: .work, isPaused: false, isComplete: false) == [.getReady(2)])
    }

    @Test func noGetReadyWhenNextPhaseIsNotWork() {
        var d = IntervalCueDecider()
        #expect(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 10, nextPhaseKind: .rest, isPaused: false, isComplete: false) == [])
        #expect(d.cues(phaseKind: .warmup, currentPhaseID: 1, phaseRemaining: 3, nextPhaseKind: .cooldown, isPaused: false, isComplete: false) == [])
    }
}
