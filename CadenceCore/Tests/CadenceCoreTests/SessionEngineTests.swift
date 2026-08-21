import XCTest
@testable import CadenceCore

/// Field-testing §02 session-engine core: wall-clock timing and the Start
/// Workout type taxonomy.
final class SessionEngineTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: WorkoutClock

    func testElapsedIsWallClock() {
        let clock = WorkoutClock(startedAt: t0)
        XCTAssertEqual(clock.elapsed(now: t0.addingTimeInterval(90)), 90, accuracy: 0.001)
    }

    func testElapsedExcludesPausedSpan() {
        var clock = WorkoutClock(startedAt: t0)
        clock.pause(now: t0.addingTimeInterval(60))           // ran 60s
        clock.resume(now: t0.addingTimeInterval(120))         // paused 60s
        // At +180s total: 60 active before pause + 60 active after resume = 120.
        XCTAssertEqual(clock.elapsed(now: t0.addingTimeInterval(180)), 120, accuracy: 0.001)
    }

    func testElapsedCorrectAcrossBackgroundGapWhilePaused() {
        var clock = WorkoutClock(startedAt: t0)
        clock.pause(now: t0.addingTimeInterval(30))
        // App backgrounded for a long time while paused; elapsed should freeze
        // at the 30s of active time, not advance.
        XCTAssertEqual(clock.elapsed(now: t0.addingTimeInterval(30 + 600)), 30, accuracy: 0.001)
    }

    func testEndFreezesElapsedAndFoldsPause() {
        var clock = WorkoutClock(startedAt: t0)
        clock.pause(now: t0.addingTimeInterval(60))
        clock.end(now: t0.addingTimeInterval(100))            // ended while paused
        XCTAssertTrue(clock.isEnded)
        // Only the first 60s were active; the 40s pause is excluded, and elapsed
        // no longer advances after end.
        XCTAssertEqual(clock.elapsed(now: t0.addingTimeInterval(10_000)), 60, accuracy: 0.001)
    }

    func testDoublePauseAndResumeAreIdempotent() {
        var clock = WorkoutClock(startedAt: t0)
        clock.pause(now: t0.addingTimeInterval(10))
        clock.pause(now: t0.addingTimeInterval(20))           // ignored
        clock.resume(now: t0.addingTimeInterval(30))
        clock.resume(now: t0.addingTimeInterval(40))          // ignored
        XCTAssertEqual(clock.elapsed(now: t0.addingTimeInterval(50)), 30, accuracy: 0.001)
    }

    // MARK: WorkoutType

    func testWorkoutTypeRouting() {
        XCTAssertTrue(WorkoutType.weights.isStrength)
        XCTAssertNil(WorkoutType.weights.cardioType)
        XCTAssertFalse(WorkoutType.run.isStrength)
        XCTAssertEqual(WorkoutType.run.cardioType, .run)
        XCTAssertEqual(WorkoutType.boxing.cardioType, .boxing)
        XCTAssertEqual(WorkoutType.swim.cardioType, .swim)
        XCTAssertTrue(WorkoutType.run.usesGPS)
        XCTAssertTrue(WorkoutType.cycle.usesGPS)
        XCTAssertTrue(WorkoutType.rowing.usesGPS)
        XCTAssertFalse(WorkoutType.boxing.usesGPS)
        XCTAssertFalse(WorkoutType.swim.usesGPS)
        XCTAssertEqual(WorkoutType.allCases.count, 9)
    }
}
