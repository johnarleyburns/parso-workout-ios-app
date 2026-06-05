import Testing
import Foundation
@testable import Cadence

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
        m.tick(); #expect(m.remaining == 0) // no underflow
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
        #expect(abs(m.progress - 0.2) < 1e-9)
    }

    @Test func zeroDurationDoesNotRun() {
        let m = RestTimerModel()
        m.start(seconds: 0)
        #expect(!m.isRunning)
        #expect(m.progress == 0)
    }
}

struct HeartRateParsingTests {

    @Test func parses8BitFormat() {
        // flags=0x00 (8-bit), value=72
        let data = Data([0x00, 72])
        #expect(HeartRateMonitor.parseHeartRate(data) == 72)
    }

    @Test func parses16BitFormat() {
        // flags=0x01 (16-bit), value=300 (0x012C) little-endian
        let data = Data([0x01, 0x2C, 0x01])
        #expect(HeartRateMonitor.parseHeartRate(data) == 300)
    }

    @Test func rejectsEmpty() {
        #expect(HeartRateMonitor.parseHeartRate(Data()) == nil)
        #expect(HeartRateMonitor.parseHeartRate(Data([0x00])) == nil)
    }
}
