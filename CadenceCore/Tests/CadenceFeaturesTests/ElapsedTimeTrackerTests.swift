import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

struct ElapsedTimeTrackerTests {

    @Test func initialState_notPaused() {
        let t = ElapsedTimeTracker()
        #expect(!t.isPaused)
        #expect(t.totalPausedDuration == 0)
    }

    @Test func elapsedWithoutPause() {
        let t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-60)
        let elapsed = t.elapsed(since: start)
        #expect(abs(elapsed - 60) <= 0.1)
    }

    @Test func pauseStopsElapsed() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-10)
        t.startPause(now: start.addingTimeInterval(10))
        let elapsed = t.elapsed(since: start, now: start.addingTimeInterval(15))
        #expect(abs(elapsed - 10) <= 0.1)
    }

    @Test func resumeContinuesElapsed() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-30)
        t.startPause(now: start.addingTimeInterval(10))
        t.resume(now: start.addingTimeInterval(15))
        let elapsed = t.elapsed(since: start, now: start.addingTimeInterval(25))
        #expect(abs(elapsed - 20) <= 0.1)
    }

    @Test func multiplePausesAccumulate() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-100)
        t.startPause(now: start.addingTimeInterval(10))
        t.resume(now: start.addingTimeInterval(20))
        t.startPause(now: start.addingTimeInterval(30))
        t.resume(now: start.addingTimeInterval(50))
        let elapsed = t.elapsed(since: start, now: start.addingTimeInterval(100))
        #expect(abs(elapsed - 70) <= 0.1)
    }

    @Test func doubleStartPause_isNoop() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-20)
        t.startPause(now: start.addingTimeInterval(5))
        t.startPause(now: start.addingTimeInterval(8))
        t.resume(now: start.addingTimeInterval(10))
        let elapsed = t.elapsed(since: start, now: start.addingTimeInterval(20))
        #expect(abs(elapsed - 15) <= 0.1)
    }

    @Test func doubleResume_isNoop() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-20)
        t.startPause(now: start.addingTimeInterval(5))
        t.resume(now: start.addingTimeInterval(10))
        t.resume(now: start.addingTimeInterval(12))
        #expect(!t.isPaused)
    }

    @Test func togglePause() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-30)
        t.togglePause(now: start.addingTimeInterval(10))
        #expect(t.isPaused)
        t.togglePause(now: start.addingTimeInterval(20))
        #expect(!t.isPaused)
        let elapsed = t.elapsed(since: start, now: start.addingTimeInterval(30))
        #expect(abs(elapsed - 20) <= 0.1)
    }

    @Test func resetClearsState() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-10)
        t.startPause(now: start.addingTimeInterval(5))
        t.reset()
        #expect(!t.isPaused)
        #expect(t.totalPausedDuration == 0)
    }

    @Test func resumeWhileNotPaused_isNoop() {
        var t = ElapsedTimeTracker()
        t.resume()
        #expect(t.totalPausedDuration == 0)
    }

    @Test func pauseWhileAlreadyPaused_isNoop() {
        var t = ElapsedTimeTracker()
        let start = Date().addingTimeInterval(-20)
        t.startPause(now: start.addingTimeInterval(5))
        let before = t.totalPausedDuration
        t.startPause(now: start.addingTimeInterval(8))
        #expect(t.totalPausedDuration == before)
    }
}
