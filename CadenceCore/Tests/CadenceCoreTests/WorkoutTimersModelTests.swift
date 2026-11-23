import Foundation
import Testing
@testable import CadenceCore

/// The strength session's single always-on work/rest interval.
struct WorkoutTimersModelTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test func startsAsRestAndCounts() {
        var m = WorkoutTimersModel()
        m.startRestIfNeeded(now: at(0))
        #expect(m.mode == .rest)
        #expect(m.isRunning)
        #expect(abs(m.elapsed(now: at(30)) - 30) <= 0.001)
    }

    @Test func openingTheEditorStartsWorkFromZero() {
        var m = WorkoutTimersModel()
        m.startRestIfNeeded(now: at(0))
        m.beginWork(now: at(40))
        #expect(m.mode == .work)
        #expect(abs(m.elapsed(now: at(55)) - 15) <= 0.001)
    }

    @Test func loggingStartsRestFromZero() {
        var m = WorkoutTimersModel()
        m.beginWork(now: at(0))
        m.beginRest(now: at(25))
        #expect(m.mode == .rest)
        #expect(abs(m.elapsed(now: at(45)) - 20) <= 0.001)
    }

    @Test func pauseFreezesAndResumeContinuesTheSameInterval() {
        var m = WorkoutTimersModel()
        m.beginWork(now: at(0))
        m.pause(now: at(12))
        #expect(!m.isRunning)
        #expect(abs(m.elapsed(now: at(100)) - 12) <= 0.001)
        m.resume(now: at(100))
        #expect(abs(m.elapsed(now: at(108)) - 20) <= 0.001)
    }

    @Test func reopeningTheSameModeDoesNotResetIt() {
        var m = WorkoutTimersModel()
        m.beginWork(now: at(0))
        m.beginWork(now: at(20))
        #expect(abs(m.elapsed(now: at(30)) - 30) <= 0.001)
    }
}
