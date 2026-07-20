import XCTest
@testable import CadenceFeatures
import CadenceCore

final class ElapsedTimeTrackerTests: XCTestCase {

    func testInitialState_notPaused() {
        let t = ElapsedTimeTracker()
        XCTAssertFalse(t.isPaused)
        XCTAssertEqual(t.totalPausedDuration, 0)
    }

    func testElapsedWithoutPause() {
        let t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-60)
        let elapsed = t.elapsed(since: start)
        XCTAssertEqual(elapsed, 60, accuracy: 0.1)
    }

    func testPauseStopsElapsed() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-10)
        t.startPause(now: start.addingTimeInterval(10))
        let elapsed = t.elapsed(since: start, now: start.addingTimeInterval(15))
        XCTAssertEqual(elapsed, 10, accuracy: 0.1)
    }

    func testResumeContinuesElapsed() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-30)
        t.startPause(now: start.addingTimeInterval(10))
        t.resume(now: start.addingTimeInterval(15))
        let elapsed = t.elapsed(since: start, now: start.addingTimeInterval(25))
        XCTAssertEqual(elapsed, 20, accuracy: 0.1)
    }

    func testMultiplePausesAccumulate() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-100)
        t.startPause(now: start.addingTimeInterval(10))
        t.resume(now: start.addingTimeInterval(20))
        t.startPause(now: start.addingTimeInterval(30))
        t.resume(now: start.addingTimeInterval(50))
        let elapsed = t.elapsed(since: start, now: start.addingTimeInterval(100))
        XCTAssertEqual(elapsed, 70, accuracy: 0.1)
    }

    func testDoubleStartPause_isNoop() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-20)
        t.startPause(now: start.addingTimeInterval(5))
        t.startPause(now: start.addingTimeInterval(8))
        t.resume(now: start.addingTimeInterval(10))
        let elapsed = t.elapsed(since: start, now: start.addingTimeInterval(20))
        XCTAssertEqual(elapsed, 15, accuracy: 0.1)
    }

    func testDoubleResume_isNoop() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-20)
        t.startPause(now: start.addingTimeInterval(5))
        t.resume(now: start.addingTimeInterval(10))
        t.resume(now: start.addingTimeInterval(12))
        XCTAssertFalse(t.isPaused)
    }

    func testTogglePause() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-30)
        t.togglePause(now: start.addingTimeInterval(10))
        XCTAssertTrue(t.isPaused)
        t.togglePause(now: start.addingTimeInterval(20))
        XCTAssertFalse(t.isPaused)
        let elapsed = t.elapsed(since: start, now: start.addingTimeInterval(30))
        XCTAssertEqual(elapsed, 20, accuracy: 0.1)
    }

    func testResetClearsState() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-10)
        t.startPause(now: start.addingTimeInterval(5))
        t.reset()
        XCTAssertFalse(t.isPaused)
        XCTAssertEqual(t.totalPausedDuration, 0)
    }

    func testResumeWhileNotPaused_isNoop() {
        var t = ElapsedTimeTracker()
        t.resume()
        XCTAssertEqual(t.totalPausedDuration, 0)
    }

    func testPauseWhileAlreadyPaused_isNoop() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-20)
        t.startPause(now: start.addingTimeInterval(5))
        let before = t.totalPausedDuration
        t.startPause(now: start.addingTimeInterval(8))
        XCTAssertEqual(t.totalPausedDuration, before)
    }
}
