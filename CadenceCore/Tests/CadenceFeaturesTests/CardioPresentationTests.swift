import XCTest
import CadenceCore
import CadenceFeatures

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

final class CardioPresentationTests: XCTestCase {

    func testRunningCannotBeDismissedOrMinimized() {
        var p = CardioPresentation()
        XCTAssertFalse(p.allowsInteractiveMinimize)
        XCTAssertFalse(p.apply(.minimize))
        XCTAssertEqual(p.state, .running)
    }

    func testPauseMinimizeReopenResumeEnd() {
        var p = CardioPresentation()
        XCTAssertTrue(p.apply(.pause))
        XCTAssertTrue(p.allowsInteractiveMinimize)
        XCTAssertTrue(p.apply(.minimize))
        XCTAssertEqual(p.state, .minimized)
        XCTAssertTrue(p.isPaused)
        XCTAssertTrue(p.apply(.reopen))
        XCTAssertEqual(p.state, .paused)
        XCTAssertTrue(p.apply(.resume))
        XCTAssertFalse(p.apply(.resume), "resume works once")
        XCTAssertTrue(p.apply(.end))
        XCTAssertFalse(p.allowsInteractiveMinimize)
        XCTAssertFalse(p.apply(.reopen))
    }

    func testEndIsDistinctFromMinimize() {
        var p = CardioPresentation.live(isPaused: true)
        p.apply(.minimize)
        XCTAssertNotEqual(p.state, .ended)
    }

    func testParkedRecorderSurvivesMinimizeReopenAndResume() {
        let loc = Loc()
        let rec = CardioRecorder(location: loc, hrm: HRM())
        rec.start(type: .boxing, usesGPS: false)
        for _ in 0..<5 { rec.tick() }
        rec.pause()
        let store = ParkedCardioStore()
        XCTAssertTrue(store.park(ParkedCardioSession(route: .record, type: .boxing, recorder: rec)))
        XCTAssertFalse(loc.stopped, "minimize must not end the recorder")
        let back = store.take()
        XCTAssertTrue(back?.recorder === rec)
        XCTAssertFalse(store.isParked)
        XCTAssertEqual(rec.elapsed, 5)
        XCTAssertTrue(rec.isRecording && rec.isPaused)
        rec.tick()
        XCTAssertEqual(rec.elapsed, 5, "still paused")
        rec.resume()
        rec.tick()
        XCTAssertEqual(rec.elapsed, 6)
    }

    func testOnlyOneParkedSession() {
        let store = ParkedCardioStore()
        let a = ParkedCardioSession(route: .swim, type: .swim)
        XCTAssertTrue(store.park(a))
        XCTAssertTrue(store.park(a))
        XCTAssertFalse(store.park(ParkedCardioSession(route: .outdoor, type: .run)))
        XCTAssertTrue(store.session === a)
    }

    func testParkedOutdoorClockAndIntervalRunnerKeepState() {
        var clock = WorkoutClock(startedAt: Date(timeIntervalSinceNow: -100))
        clock.pause(now: Date())
        let outdoor = ParkedCardioSession(route: .outdoor, type: .run, clock: clock, goalMeters: 5000)
        XCTAssertTrue(outdoor.clock.isPaused)
        XCTAssertEqual(outdoor.goalMeters, 5000)
        let swim = ParkedCardioSession(route: .swim, type: .swim, laps: 7, targetLaps: 20)
        XCTAssertEqual(swim.laps, 7)
    }
}
