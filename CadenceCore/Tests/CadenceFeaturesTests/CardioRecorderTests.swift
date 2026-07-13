import XCTest
import CadenceCore
import CadenceFeatures

private final class FakeLocation: LocationTracking {
    var fixes: [LocationFix] = []
    private(set) var started = false
    private(set) var stopped = false
    func start() { started = true }
    func stop() { stopped = true }
}

private final class FakeHRM: HeartRateMonitoring {
    var state: HRMConnectionState = .idle
    var currentBPM: Double?
    var battery: Int?
    var connectionError: String?
    var criticalBattery = false
    var discovered: [DiscoveredHRM] = []
    private(set) var scanning = false
    private(set) var connectedID: UUID?
    func startScanning() { scanning = true }
    func stopScanning() { scanning = false }
    func connect(_ id: UUID) { connectedID = id; state = .connected(id) }
    func disconnect() { state = .idle }
    func restoreDefaultDevice(_ id: UUID) {}
    func injectExternalBPM(_ bpm: Double) { currentBPM = bpm }
}

final class CardioRecorderTests: XCTestCase {

    func testStartBeginsRecordingAndStartsGPSForGPSType() {
        let loc = FakeLocation(); let hrm = FakeHRM()
        let rec = CardioRecorder(location: loc, hrm: hrm)
        rec.start(type: .run)
        XCTAssertTrue(rec.isRecording)
        XCTAssertFalse(rec.isPaused)
        XCTAssertTrue(loc.started)
    }

    func testNonGPSTypeDoesNotStartLocation() {
        let loc = FakeLocation(); let hrm = FakeHRM()
        let rec = CardioRecorder(location: loc, hrm: hrm)
        rec.start(type: .boxing)
        XCTAssertFalse(loc.started)
    }

    func testTickCapturesHeartRateSamples() {
        let loc = FakeLocation(); let hrm = FakeHRM()
        hrm.currentBPM = 150
        let rec = CardioRecorder(location: loc, hrm: hrm)
        rec.start(type: .run)
        rec.tick(); rec.tick()
        XCTAssertEqual(rec.elapsed, 2)
        XCTAssertEqual(rec.hrSamples.count, 2)
        XCTAssertEqual(rec.avgHR, 150)
    }

    func testPauseStopsTicking() {
        let rec = CardioRecorder(location: FakeLocation(), hrm: FakeHRM())
        rec.start(type: .run)
        rec.pause()
        rec.tick()
        XCTAssertEqual(rec.elapsed, 0)
    }

    func testEndReturnsSummaryAndStopsGPS() {
        let loc = FakeLocation(); let hrm = FakeHRM()
        loc.fixes = [LocationFix(t: 0, lat: 0, lon: 0), LocationFix(t: 10, lat: 0.001, lon: 0.001)]
        hrm.currentBPM = 140
        let rec = CardioRecorder(location: loc, hrm: hrm)
        rec.start(type: .run)
        rec.tick()
        let summary = rec.end()
        XCTAssertFalse(rec.isRecording)
        XCTAssertTrue(loc.stopped)
        XCTAssertEqual(summary.type, .run)
        XCTAssertEqual(summary.hrSamples.count, 1)
        XCTAssertNotNil(summary.distanceMeters)
        XCTAssertGreaterThan(summary.distanceMeters ?? 0, 0)
    }

    func testConnectStrapScansAndConnectsFirstDiscovered() {
        let hrm = FakeHRM()
        let id = UUID()
        hrm.discovered = [DiscoveredHRM(id: id, name: "Polar H10")]
        let rec = CardioRecorder(location: FakeLocation(), hrm: hrm)
        rec.connectStrap()
        XCTAssertTrue(hrm.scanning)
        XCTAssertEqual(hrm.connectedID, id)
        XCTAssertTrue(rec.strapConnected)
    }
}
