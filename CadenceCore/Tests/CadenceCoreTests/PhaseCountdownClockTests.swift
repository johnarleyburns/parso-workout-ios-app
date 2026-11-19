import Foundation
import Testing
@testable import CadenceCore

/// Proves the warm-up / cool-down countdown is wall-clock based: it keeps counting
/// down across a backgrounded gap and only freezes when explicitly paused.
struct PhaseCountdownClockTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test func startsFullAndCountsDown() {
        let clock = PhaseCountdownClock(total: 300, startedAt: t0)
        #expect(clock.remaining(now: t0) == 300)
        #expect(clock.remaining(now: at(60)) == 240)
        #expect(clock.consumed(now: at(60)) == 60)
        #expect(!clock.isFinished(now: at(60)))
    }

    /// THE BUG: a 5-minute cool-down backgrounded at 0:30 and returned to at 4:30
    /// must show ~0:00 remaining, not stay frozen at 4:30. Because elapsed is
    /// date-derived, the gap counts.
    @Test func keepsRunningAcrossBackgroundGap() {
        let clock = PhaseCountdownClock(total: 300, startedAt: t0)
        // App backgrounded at 30s in, returns 240s later (total 270s elapsed).
        #expect(clock.remaining(now: at(270)) == 30, "time must elapse while backgrounded")
        // Returns after the phase would have completed.
        #expect(clock.isFinished(now: at(360)), "a cool-down that ends while backgrounded is finished on return")
        #expect(clock.remaining(now: at(360)) == 0)
    }

    @Test func explicitPauseFreezesRemaining() {
        var clock = PhaseCountdownClock(total: 300, startedAt: t0)
        clock.pause(now: at(60))                       // 240 remaining, paused
        // Even though wall-clock advances a lot, remaining stays frozen while paused.
        #expect(clock.remaining(now: at(60)) == 240)
        #expect(clock.remaining(now: at(600)) == 240, "paused countdown must not advance")
        #expect(clock.isPaused)
    }

    @Test func resumeContinuesFromWhereItPaused() {
        var clock = PhaseCountdownClock(total: 300, startedAt: t0)
        clock.pause(now: at(60))                       // 240 remaining
        clock.resume(now: at(600))                     // paused span (540s) folded out
        #expect(!clock.isPaused)
        #expect(clock.remaining(now: at(600)) == 240, "resume continues from the pause point")
        #expect(clock.remaining(now: at(660)) == 180, "counts down again after resume")
    }

    @Test func consumedClampsToTotalAtNaturalEnd() {
        let clock = PhaseCountdownClock(total: 300, startedAt: t0)
        #expect(clock.consumed(now: at(1000)) == 300, "consumed never exceeds total")
    }

    @Test func skipReportsPartialConsumed() {
        let clock = PhaseCountdownClock(total: 600, startedAt: t0)
        // Skipped at 3:00 → 180 consumed.
        #expect(clock.consumed(now: at(180)) == 180)
    }

    @Test func doublePauseAndResumeAreIdempotent() {
        var clock = PhaseCountdownClock(total: 300, startedAt: t0)
        clock.pause(now: at(30))
        clock.pause(now: at(45))                       // no-op
        clock.resume(now: at(90))
        clock.resume(now: at(120))                     // no-op
        // Only the first pause span (30→90 = 60s) is excluded: 120s wall − 60s
        // paused = 60s consumed → 240 remaining.
        #expect(clock.remaining(now: at(120)) == 240)
    }

    @Test func addTimeExtendsPhase() {
        var clock = PhaseCountdownClock(total: 300, startedAt: t0)
        // 2:00 in (120s consumed), 180s remaining. Add 60s → 240 remaining.
        clock.addTime(60)
        #expect(clock.total == 360)
        #expect(clock.remaining(now: at(120)) == 240)
    }

    @Test func addTimeRevivesFinishedPhase() {
        var clock = PhaseCountdownClock(total: 60, startedAt: t0)
        #expect(clock.isFinished(now: at(120)))
        clock.addTime(60, now: at(120))
        #expect(!clock.isFinished(now: at(120)), "addTime should revive a finished phase")
        #expect(clock.total == 60, "restarts with just the added seconds")
        #expect(clock.remaining(now: at(120)) == 60, "full 60s remaining from the restart")
    }
}
