import XCTest
import CadenceCore
import CadenceFeatures

final class IntervalCueDeciderTests: XCTestCase {

    func testFiresWarningOncePerWorkPhase() {
        var d = IntervalCueDecider()
        // 30s left in work phase 3 → warning fires once.
        XCTAssertEqual(d.cues(phaseKind: .work, currentPhaseID: 3, phaseRemaining: 30, isPaused: false, isComplete: false), [.warning])
        // Same phase, still 30 → no repeat.
        XCTAssertEqual(d.cues(phaseKind: .work, currentPhaseID: 3, phaseRemaining: 30, isPaused: false, isComplete: false), [])
    }

    func testWarningRearmsForNewPhase() {
        var d = IntervalCueDecider()
        _ = d.cues(phaseKind: .work, currentPhaseID: 3, phaseRemaining: 30, isPaused: false, isComplete: false)
        XCTAssertEqual(d.cues(phaseKind: .work, currentPhaseID: 5, phaseRemaining: 30, isPaused: false, isComplete: false), [.warning])
    }

    func testCountdownTicksOnFinalThreeSeconds() {
        var d = IntervalCueDecider()
        XCTAssertEqual(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 3, isPaused: false, isComplete: false), [.countdownTick])
        XCTAssertEqual(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 2, isPaused: false, isComplete: false), [.countdownTick])
        XCTAssertEqual(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 2, isPaused: false, isComplete: false), [])
    }

    func testNoCuesDuringRestPhase() {
        var d = IntervalCueDecider()
        XCTAssertEqual(d.cues(phaseKind: .rest, currentPhaseID: 2, phaseRemaining: 3, isPaused: false, isComplete: false), [])
        XCTAssertEqual(d.cues(phaseKind: .rest, currentPhaseID: 2, phaseRemaining: 30, isPaused: false, isComplete: false), [])
    }

    func testNoCuesWhenPausedOrComplete() {
        var d = IntervalCueDecider()
        XCTAssertEqual(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 30, isPaused: true, isComplete: false), [])
        XCTAssertEqual(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 3, isPaused: false, isComplete: true), [])
    }

    func testResetRearmsCountdown() {
        var d = IntervalCueDecider()
        _ = d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 3, isPaused: false, isComplete: false)
        d.reset()
        XCTAssertEqual(d.cues(phaseKind: .work, currentPhaseID: 1, phaseRemaining: 3, isPaused: false, isComplete: false), [.countdownTick])
    }
}
