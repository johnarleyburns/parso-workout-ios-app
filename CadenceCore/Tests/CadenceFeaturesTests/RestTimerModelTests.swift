import Testing
import CadenceFeatures
import CadenceWorkoutFeatures

/// Moved from Cadence/CadenceTests/CadenceTests.swift (test-pyramid Phase 2).
struct RestTimerModelTests {
    @Test func startSetsRemainingAndRuns() {
        let m = RestTimerModel()
        m.start(seconds: 90)
        #expect(m.remaining == 90)
        #expect(m.total == 90)
        #expect(m.isRunning)
    }

    @Test func tickDecrementsAndStopsAtZero() {
        let m = RestTimerModel()
        m.start(seconds: 2)
        m.tick(); #expect(m.remaining == 1); #expect(m.isRunning)
        m.tick(); #expect(m.remaining == 0); #expect(!m.isRunning)
        m.tick(); #expect(m.remaining == 0)
    }

    @Test func skipStopsImmediately() {
        let m = RestTimerModel()
        m.start(seconds: 90)
        m.skip()
        #expect(m.remaining == 0)
        #expect(!m.isRunning)
    }

    @Test func add30ExtendsRunningTimer() {
        let m = RestTimerModel()
        m.start(seconds: 10)
        m.add(30)
        #expect(m.remaining == 40)
    }

    @Test func progressReflectsElapsed() {
        let m = RestTimerModel()
        m.start(seconds: 10)
        m.tick(); m.tick()
        #expect(abs(m.progress - 0.2) <= 1e-9)
    }

    @Test func zeroDurationDoesNotRun() {
        let m = RestTimerModel()
        m.start(seconds: 0)
        #expect(!m.isRunning)
        #expect(m.progress == 0)
    }
}
