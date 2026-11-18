import Foundation
import Testing
@testable import CadenceCore

/// Field-testing §02 session-engine core: wall-clock timing and the Start
/// Workout type taxonomy.
struct SessionEngineTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: WorkoutClock

    @Test func elapsedIsWallClock() {
        let clock = WorkoutClock(startedAt: t0)
        #expect(abs(clock.elapsed(now: t0.addingTimeInterval(90)) - 90) <= 0.001)
    }

    @Test func elapsedExcludesPausedSpan() {
        var clock = WorkoutClock(startedAt: t0)
        clock.pause(now: t0.addingTimeInterval(60))           // ran 60s
        clock.resume(now: t0.addingTimeInterval(120))         // paused 60s
        // At +180s total: 60 active before pause + 60 active after resume = 120.
        #expect(abs(clock.elapsed(now: t0.addingTimeInterval(180)) - 120) <= 0.001)
    }

    @Test func elapsedCorrectAcrossBackgroundGapWhilePaused() {
        var clock = WorkoutClock(startedAt: t0)
        clock.pause(now: t0.addingTimeInterval(30))
        // App backgrounded for a long time while paused; elapsed should freeze
        // at the 30s of active time, not advance.
        #expect(abs(clock.elapsed(now: t0.addingTimeInterval(30 + 600)) - 30) <= 0.001)
    }

    @Test func endFreezesElapsedAndFoldsPause() {
        var clock = WorkoutClock(startedAt: t0)
        clock.pause(now: t0.addingTimeInterval(60))
        clock.end(now: t0.addingTimeInterval(100))            // ended while paused
        #expect(clock.isEnded)
        // Only the first 60s were active; the 40s pause is excluded, and elapsed
        // no longer advances after end.
        #expect(abs(clock.elapsed(now: t0.addingTimeInterval(10_000)) - 60) <= 0.001)
    }

    @Test func doublePauseAndResumeAreIdempotent() {
        var clock = WorkoutClock(startedAt: t0)
        clock.pause(now: t0.addingTimeInterval(10))
        clock.pause(now: t0.addingTimeInterval(20))           // ignored
        clock.resume(now: t0.addingTimeInterval(30))
        clock.resume(now: t0.addingTimeInterval(40))          // ignored
        #expect(abs(clock.elapsed(now: t0.addingTimeInterval(50)) - 30) <= 0.001)
    }

    // MARK: WorkoutType

    @Test func workoutTypeRouting() {
        #expect(WorkoutType.weights.isStrength)
        #expect(WorkoutType.weights.cardioType == nil)
        #expect(!WorkoutType.run.isStrength)
        #expect(WorkoutType.run.cardioType == .run)
        #expect(WorkoutType.boxing.cardioType == .boxing)
        #expect(WorkoutType.swim.cardioType == .swim)
        #expect(WorkoutType.run.usesGPS)
        #expect(WorkoutType.cycle.usesGPS)
        #expect(WorkoutType.rowing.usesGPS)
        #expect(!WorkoutType.boxing.usesGPS)
        #expect(!WorkoutType.swim.usesGPS)
        #expect(WorkoutType.allCases.count == 11)
    }
}
