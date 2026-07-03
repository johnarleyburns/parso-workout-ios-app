import XCTest
@testable import CadenceCore

/// Proves the warm-up / cool-down countdown is wall-clock based: it keeps counting
/// down across a backgrounded gap and only freezes when explicitly paused.
final class PhaseCountdownClockTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testStartsFullAndCountsDown() {
        let clock = PhaseCountdownClock(total: 300, startedAt: t0)
        XCTAssertEqual(clock.remaining(now: t0), 300)
        XCTAssertEqual(clock.remaining(now: at(60)), 240)
        XCTAssertEqual(clock.consumed(now: at(60)), 60)
        XCTAssertFalse(clock.isFinished(now: at(60)))
    }

    /// THE BUG: a 5-minute cool-down backgrounded at 0:30 and returned to at 4:30
    /// must show ~0:00 remaining, not stay frozen at 4:30. Because elapsed is
    /// date-derived, the gap counts.
    func testKeepsRunningAcrossBackgroundGap() {
        let clock = PhaseCountdownClock(total: 300, startedAt: t0)
        // App backgrounded at 30s in, returns 240s later (total 270s elapsed).
        XCTAssertEqual(clock.remaining(now: at(270)), 30, "time must elapse while backgrounded")
        // Returns after the phase would have completed.
        XCTAssertTrue(clock.isFinished(now: at(360)), "a cool-down that ends while backgrounded is finished on return")
        XCTAssertEqual(clock.remaining(now: at(360)), 0)
    }

    func testExplicitPauseFreezesRemaining() {
        var clock = PhaseCountdownClock(total: 300, startedAt: t0)
        clock.pause(now: at(60))                       // 240 remaining, paused
        // Even though wall-clock advances a lot, remaining stays frozen while paused.
        XCTAssertEqual(clock.remaining(now: at(60)), 240)
        XCTAssertEqual(clock.remaining(now: at(600)), 240, "paused countdown must not advance")
        XCTAssertTrue(clock.isPaused)
    }

    func testResumeContinuesFromWhereItPaused() {
        var clock = PhaseCountdownClock(total: 300, startedAt: t0)
        clock.pause(now: at(60))                       // 240 remaining
        clock.resume(now: at(600))                     // paused span (540s) folded out
        XCTAssertFalse(clock.isPaused)
        XCTAssertEqual(clock.remaining(now: at(600)), 240, "resume continues from the pause point")
        XCTAssertEqual(clock.remaining(now: at(660)), 180, "counts down again after resume")
    }

    func testConsumedClampsToTotalAtNaturalEnd() {
        let clock = PhaseCountdownClock(total: 300, startedAt: t0)
        XCTAssertEqual(clock.consumed(now: at(1000)), 300, "consumed never exceeds total")
    }

    func testSkipReportsPartialConsumed() {
        let clock = PhaseCountdownClock(total: 600, startedAt: t0)
        // Skipped at 3:00 → 180 consumed.
        XCTAssertEqual(clock.consumed(now: at(180)), 180)
    }

    func testDoublePauseAndResumeAreIdempotent() {
        var clock = PhaseCountdownClock(total: 300, startedAt: t0)
        clock.pause(now: at(30))
        clock.pause(now: at(45))                       // no-op
        clock.resume(now: at(90))
        clock.resume(now: at(120))                     // no-op
        // Only the first pause span (30→90 = 60s) is excluded: 120s wall − 60s
        // paused = 60s consumed → 240 remaining.
        XCTAssertEqual(clock.remaining(now: at(120)), 240)
    }
}
