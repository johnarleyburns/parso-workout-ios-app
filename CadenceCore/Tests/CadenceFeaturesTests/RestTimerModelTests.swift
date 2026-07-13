import XCTest
import CadenceFeatures

/// Moved from Cadence/CadenceTests/CadenceTests.swift (test-pyramid Phase 2).
final class RestTimerModelTests: XCTestCase {
    func testStartSetsRemainingAndRuns() {
        let m = RestTimerModel()
        m.start(seconds: 90)
        XCTAssertEqual(m.remaining, 90)
        XCTAssertEqual(m.total, 90)
        XCTAssertTrue(m.isRunning)
    }

    func testTickDecrementsAndStopsAtZero() {
        let m = RestTimerModel()
        m.start(seconds: 2)
        m.tick(); XCTAssertEqual(m.remaining, 1); XCTAssertTrue(m.isRunning)
        m.tick(); XCTAssertEqual(m.remaining, 0); XCTAssertFalse(m.isRunning)
        m.tick(); XCTAssertEqual(m.remaining, 0)
    }

    func testSkipStopsImmediately() {
        let m = RestTimerModel()
        m.start(seconds: 90)
        m.skip()
        XCTAssertEqual(m.remaining, 0)
        XCTAssertFalse(m.isRunning)
    }

    func testAdd30ExtendsRunningTimer() {
        let m = RestTimerModel()
        m.start(seconds: 10)
        m.add(30)
        XCTAssertEqual(m.remaining, 40)
    }

    func testProgressReflectsElapsed() {
        let m = RestTimerModel()
        m.start(seconds: 10)
        m.tick(); m.tick()
        XCTAssertEqual(m.progress, 0.2, accuracy: 1e-9)
    }

    func testZeroDurationDoesNotRun() {
        let m = RestTimerModel()
        m.start(seconds: 0)
        XCTAssertFalse(m.isRunning)
        XCTAssertEqual(m.progress, 0)
    }
}
