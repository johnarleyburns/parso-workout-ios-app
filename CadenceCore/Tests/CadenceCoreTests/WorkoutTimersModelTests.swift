import XCTest
@testable import CadenceCore

/// P6 (issue 9) — the strength session's work/rest stopwatch. Exactly one mode
/// runs at a time; switching banks the previous span.
final class WorkoutTimersModelTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testStartsIdle() {
        let m = WorkoutTimersModel()
        XCTAssertEqual(m.mode, .idle)
        XCTAssertEqual(m.elapsed(.work, now: at(10)), 0)
        XCTAssertEqual(m.elapsed(.rest, now: at(10)), 0)
    }

    func testWorkAccumulatesWhileRunning() {
        var m = WorkoutTimersModel()
        m.toggle(.work, now: at(0))
        XCTAssertEqual(m.mode, .work)
        XCTAssertEqual(m.elapsed(.work, now: at(30)), 30, accuracy: 0.001)
    }

    func testSwitchingBanksPreviousSpan() {
        var m = WorkoutTimersModel()
        m.toggle(.work, now: at(0))
        m.toggle(.rest, now: at(40))   // 40s of work banked, rest starts
        XCTAssertEqual(m.mode, .rest)
        XCTAssertEqual(m.elapsed(.work, now: at(70)), 40, accuracy: 0.001, "work is frozen while resting")
        XCTAssertEqual(m.elapsed(.rest, now: at(70)), 30, accuracy: 0.001)
    }

    func testTogglingActiveModeStopsIt() {
        var m = WorkoutTimersModel()
        m.toggle(.work, now: at(0))
        m.toggle(.work, now: at(25))   // tap Work again → idle
        XCTAssertEqual(m.mode, .idle)
        XCTAssertEqual(m.elapsed(.work, now: at(100)), 25, accuracy: 0.001, "banked, no longer counting")
    }

    func testResumingAModeAccumulates() {
        var m = WorkoutTimersModel()
        m.toggle(.work, now: at(0))
        m.toggle(.rest, now: at(20))
        m.toggle(.work, now: at(50))   // back to work; +? from 50
        XCTAssertEqual(m.elapsed(.work, now: at(60)), 30, accuracy: 0.001, "20 banked + 10 running")
        XCTAssertEqual(m.elapsed(.rest, now: at(60)), 30, accuracy: 0.001)
    }

    func testStopBanksAndGoesIdle() {
        var m = WorkoutTimersModel()
        m.toggle(.work, now: at(0))
        m.stop(now: at(15))
        XCTAssertEqual(m.mode, .idle)
        XCTAssertEqual(m.elapsed(.work, now: at(999)), 15, accuracy: 0.001)
    }
}
