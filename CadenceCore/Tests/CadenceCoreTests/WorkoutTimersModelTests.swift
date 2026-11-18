import Foundation
import Testing
@testable import CadenceCore

/// P6 (issue 9) — the strength session's work/rest stopwatch. Exactly one mode
/// runs at a time; switching banks the previous span.
struct WorkoutTimersModelTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test func startsIdle() {
        let m = WorkoutTimersModel()
        #expect(m.mode == .idle)
        #expect(m.elapsed(.work, now: at(10)) == 0)
        #expect(m.elapsed(.rest, now: at(10)) == 0)
    }

    @Test func workAccumulatesWhileRunning() {
        var m = WorkoutTimersModel()
        m.toggle(.work, now: at(0))
        #expect(m.mode == .work)
        #expect(abs(m.elapsed(.work, now: at(30)) - 30) <= 0.001)
    }

    @Test func switchingBanksPreviousSpan() {
        var m = WorkoutTimersModel()
        m.toggle(.work, now: at(0))
        m.toggle(.rest, now: at(40))   // 40s of work banked, rest starts
        #expect(m.mode == .rest)
        #expect(abs(m.elapsed(.work, now: at(70)) - 40) <= 0.001, "work is frozen while resting")
        #expect(abs(m.elapsed(.rest, now: at(70)) - 30) <= 0.001)
    }

    @Test func togglingActiveModeStopsIt() {
        var m = WorkoutTimersModel()
        m.toggle(.work, now: at(0))
        m.toggle(.work, now: at(25))   // tap Work again → idle
        #expect(m.mode == .idle)
        #expect(abs(m.elapsed(.work, now: at(100)) - 25) <= 0.001, "banked, no longer counting")
    }

    @Test func resumingAModeAccumulates() {
        var m = WorkoutTimersModel()
        m.toggle(.work, now: at(0))
        m.toggle(.rest, now: at(20))
        m.toggle(.work, now: at(50))   // back to work; +? from 50
        #expect(abs(m.elapsed(.work, now: at(60)) - 30) <= 0.001, "20 banked + 10 running")
        #expect(abs(m.elapsed(.rest, now: at(60)) - 30) <= 0.001)
    }

    @Test func stopBanksAndGoesIdle() {
        var m = WorkoutTimersModel()
        m.toggle(.work, now: at(0))
        m.stop(now: at(15))
        #expect(m.mode == .idle)
        #expect(abs(m.elapsed(.work, now: at(999)) - 15) <= 0.001)
    }
}
