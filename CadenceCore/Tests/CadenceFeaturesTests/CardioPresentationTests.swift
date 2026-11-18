import Foundation
import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

private final class Loc: LocationTracking {
    var fixes: [LocationFix] = []
    private(set) var stopped = false
    func start() {}
    func stop() { stopped = true }
}

private final class HRM: HeartRateMonitoring {
    var state: HRMConnectionState = .idle
    var currentBPM: Double?
    var battery: Int?
    var connectionError: String?
    var criticalBattery = false
    var discovered: [DiscoveredHRM] = []
    func startScanning() {}
    func stopScanning() {}
    func connect(_ id: UUID) {}
    func disconnect() {}
    func restoreDefaultDevice(_ id: UUID) {}
    func injectExternalBPM(_ bpm: Double) { currentBPM = bpm }
}

struct CardioPresentationTests {

    @Test func runningCannotBeDismissedOrMinimized() {
        var p = CardioPresentation()
        #expect(!p.allowsInteractiveMinimize)
        let minimized = p.apply(.minimize)
        #expect(!minimized)
        #expect(p.state == .running)
    }

    @Test func pauseMinimizeReopenResumeEnd() {
        var p = CardioPresentation()
        let paused = p.apply(.pause)
        #expect(paused)
        #expect(p.allowsInteractiveMinimize)
        let minimized = p.apply(.minimize)
        #expect(minimized)
        #expect(p.state == .minimized)
        #expect(p.isPaused)
        let reopened = p.apply(.reopen)
        #expect(reopened)
        #expect(p.state == .paused)
        let resumed = p.apply(.resume)
        #expect(resumed)
        let resumedAgain = p.apply(.resume)
        #expect(!resumedAgain, "resume works once")
        let ended = p.apply(.end)
        #expect(ended)
        #expect(!p.allowsInteractiveMinimize)
        let reopenedAfterEnd = p.apply(.reopen)
        #expect(!reopenedAfterEnd)
    }

    @Test func endIsDistinctFromMinimize() {
        var p = CardioPresentation.live(isPaused: true)
        p.apply(.minimize)
        #expect(p.state != .ended)
    }

    @Test func parkedRecorderSurvivesMinimizeReopenAndResume() {
        let loc = Loc()
        let rec = CardioRecorder(location: loc, hrm: HRM())
        rec.start(type: .boxing, usesGPS: false)
        for _ in 0..<5 { rec.tick() }
        rec.pause()
        let store = ParkedCardioStore()
        #expect(store.park(ParkedCardioSession(route: .record, type: .boxing, recorder: rec)))
        #expect(!loc.stopped, "minimize must not end the recorder")
        let back = store.take()
        #expect(back?.recorder === rec)
        #expect(!store.isParked)
        #expect(rec.elapsed == 5)
        #expect(rec.isRecording && rec.isPaused)
        rec.tick()
        #expect(rec.elapsed == 5, "still paused")
        rec.resume()
        rec.tick()
        #expect(rec.elapsed == 6)
    }

    @Test func onlyOneParkedSession() {
        let store = ParkedCardioStore()
        let a = ParkedCardioSession(route: .swim, type: .swim)
        #expect(store.park(a))
        #expect(store.park(a))
        #expect(!store.park(ParkedCardioSession(route: .outdoor, type: .run)))
        #expect(store.session === a)
    }

    @Test func parkedOutdoorClockAndIntervalRunnerKeepState() {
        var clock = WorkoutClock(startedAt: Date(timeIntervalSinceNow: -100))
        clock.pause(now: Date())
        let outdoor = ParkedCardioSession(route: .outdoor, type: .run, clock: clock, goalMeters: 5000)
        #expect(outdoor.clock.isPaused)
        #expect(outdoor.goalMeters == 5000)
        let swim = ParkedCardioSession(route: .swim, type: .swim, laps: 7, targetLaps: 20)
        #expect(swim.laps == 7)
    }
}
