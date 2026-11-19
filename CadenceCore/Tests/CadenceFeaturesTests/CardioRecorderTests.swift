import Foundation
import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

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

struct CardioRecorderTests {

    @Test func startBeginsRecordingAndStartsGPSForGPSType() {
        let loc = FakeLocation(); let hrm = FakeHRM()
        let rec = CardioRecorder(location: loc, hrm: hrm)
        rec.start(type: .run)
        #expect(rec.isRecording)
        #expect(!rec.isPaused)
        #expect(loc.started)
    }

    @Test func nonGPSTypeDoesNotStartLocation() {
        let loc = FakeLocation(); let hrm = FakeHRM()
        let rec = CardioRecorder(location: loc, hrm: hrm)
        rec.start(type: .boxing)
        #expect(!loc.started)
    }

    @Test func indoorDistanceActivityDoesNotStartLocationOrSaveRoute() {
        let loc = FakeLocation(); let hrm = FakeHRM()
        loc.fixes = [LocationFix(t: 0, lat: 0, lon: 0), LocationFix(t: 10, lat: 0.001, lon: 0.001)]
        let rec = CardioRecorder(location: loc, hrm: hrm)
        rec.start(type: .run, usesGPS: false)

        #expect(rec.isRecording)
        #expect(!rec.usesGPS)
        #expect(!loc.started)
        #expect(rec.distanceMeters == 0)

        let summary = rec.end()
        #expect(!loc.stopped)
        #expect(summary.distanceMeters == nil)
        #expect(summary.route.isEmpty)
    }

    @Test func tickCapturesHeartRateSamples() {
        let loc = FakeLocation(); let hrm = FakeHRM()
        hrm.currentBPM = 150
        let rec = CardioRecorder(location: loc, hrm: hrm)
        rec.start(type: .run)
        rec.tick(); rec.tick()
        #expect(rec.elapsed == 2)
        #expect(rec.hrSamples.count == 2)
        #expect(rec.avgHR == 150)
    }

    @Test func pauseStopsTicking() {
        let rec = CardioRecorder(location: FakeLocation(), hrm: FakeHRM())
        rec.start(type: .run)
        rec.pause()
        rec.tick()
        #expect(rec.elapsed == 0)
    }

    @Test func endReturnsSummaryAndStopsGPS() {
        let loc = FakeLocation(); let hrm = FakeHRM()
        loc.fixes = [LocationFix(t: 0, lat: 0, lon: 0), LocationFix(t: 10, lat: 0.001, lon: 0.001)]
        hrm.currentBPM = 140
        let rec = CardioRecorder(location: loc, hrm: hrm)
        rec.start(type: .run)
        rec.tick()
        let summary = rec.end()
        #expect(!rec.isRecording)
        #expect(loc.stopped)
        #expect(summary.type == .run)
        #expect(summary.hrSamples.count == 1)
        #expect(summary.distanceMeters != nil)
        #expect((summary.distanceMeters ?? 0) > 0)
    }

    @Test func connectStrapScansAndConnectsFirstDiscovered() {
        let hrm = FakeHRM()
        let id = UUID()
        hrm.discovered = [DiscoveredHRM(id: id, name: "Polar H10")]
        let rec = CardioRecorder(location: FakeLocation(), hrm: hrm)
        rec.connectStrap()
        #expect(hrm.scanning)
        #expect(hrm.connectedID == id)
        #expect(rec.strapConnected)
    }
}
