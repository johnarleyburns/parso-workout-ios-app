import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchCardioInactivityTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func tracker(_ p: CardioSensorProfile = .outdoor, owns: Bool = true) -> WatchCardioInactivityTracker {
        let t = WatchCardioInactivityTracker(store: InMemoryWatchCardioInactivityStore())
        t.begin(type: .run, profile: p, ownsSession: owns, now: t0)
        return t
    }

    func testOutdoorPausesAtTenMinutesAndEndsAfterGrace() {
        let t = tracker()
        XCTAssertEqual(t.evaluate(now: t0.addingTimeInterval(599), enabled: true), .none)
        XCTAssertEqual(t.evaluate(now: t0.addingTimeInterval(600), enabled: true), .autoPause(at: t0.addingTimeInterval(600)))
        t.recordAutoPause(at: t0.addingTimeInterval(600))
        XCTAssertEqual(t.evaluate(now: t0.addingTimeInterval(600 + 1799), enabled: true), .none)
        XCTAssertEqual(t.evaluate(now: t0.addingTimeInterval(600 + 1800 + 5), enabled: true),
                       .autoEnd(at: t0.addingTimeInterval(2400)))
        // Duration excludes the automatic pause.
        XCTAssertEqual(t.record?.activeDuration(endedAt: t0.addingTimeInterval(2400)), 600)
    }

    func testMovingAtNineFiftyNineExtendsDeadline() {
        let t = tracker()
        XCTAssertTrue(t.recordEvidence(.distance(totalMeters: 50), at: t0.addingTimeInterval(599)))
        XCTAssertEqual(t.evaluate(now: t0.addingTimeInterval(600), enabled: true), .none)
        XCTAssertEqual(t.record?.nextDeadline(), t0.addingTimeInterval(1199))
    }

    func testRepeatedAndTinyDistanceDoNotExtend() {
        let t = tracker()
        XCTAssertTrue(t.recordEvidence(.distance(totalMeters: 50), at: t0.addingTimeInterval(100)))
        XCTAssertFalse(t.recordEvidence(.distance(totalMeters: 50), at: t0.addingTimeInterval(500)))
        XCTAssertFalse(t.recordEvidence(.distance(totalMeters: 54), at: t0.addingTimeInterval(500)))
        XCTAssertFalse(t.recordEvidence(.passive(.watchRelayHeartbeat), at: t0.addingTimeInterval(500)))
    }

    func testIndoorHeartRateQualificationAndStaleDuplicates() {
        let t = tracker(.indoor)
        let s = t0.addingTimeInterval(300)
        XCTAssertFalse(t.recordEvidence(.distance(totalMeters: 500), at: s)) // distance ignored indoors? recorded but not counted
        XCTAssertTrue(t.recordEvidence(.heartRate(bpm: 130, sampleAt: s, restingHR: 60, maxHR: nil), at: s))
        // Duplicate sample, stale sample, low HR do not extend.
        XCTAssertFalse(t.recordEvidence(.heartRate(bpm: 130, sampleAt: s, restingHR: 60, maxHR: nil), at: s.addingTimeInterval(10)))
        XCTAssertFalse(t.recordEvidence(.heartRate(bpm: 140, sampleAt: s.addingTimeInterval(1), restingHR: nil, maxHR: nil),
                                        at: s.addingTimeInterval(500)))
        XCTAssertFalse(t.recordEvidence(.heartRate(bpm: 70, sampleAt: s.addingTimeInterval(20), restingHR: 60, maxHR: nil),
                                        at: s.addingTimeInterval(20)))
        XCTAssertEqual(t.record?.nextDeadline(), s.addingTimeInterval(600))
    }

    func testUserResumePreventsTerminalEndAndManualPauseNeverEnds() {
        let t = tracker()
        t.recordAutoPause(at: t0.addingTimeInterval(600))
        XCTAssertTrue(t.recordResume(at: t0.addingTimeInterval(1000)))
        XCTAssertEqual(t.evaluate(now: t0.addingTimeInterval(5000), enabled: true),
                       .autoPause(at: t0.addingTimeInterval(1600)))
        XCTAssertEqual(t.record?.pausedAccumulated, 400)

        let m = tracker()
        m.recordManualPause(at: t0.addingTimeInterval(60))
        XCTAssertEqual(m.evaluate(now: t0.addingTimeInterval(100_000), enabled: true), .none)
    }

    func testResumeRefusedAfterTerminalDeadline() {
        let t = tracker()
        t.recordAutoPause(at: t0.addingTimeInterval(600))
        XCTAssertFalse(t.recordResume(at: t0.addingTimeInterval(2500)))
        XCTAssertEqual(t.evaluate(now: t0.addingTimeInterval(2500), enabled: true), .autoEnd(at: t0.addingTimeInterval(2400)))
    }

    func testRelaunchRecoveryUsesDurableRecordAndLayeredOwnership() {
        let store = InMemoryWatchCardioInactivityStore()
        WatchCardioInactivityTracker(store: store).begin(type: .run, profile: .outdoor, ownsSession: false, now: t0)
        let reloaded = WatchCardioInactivityTracker(store: store)
        XCTAssertEqual(reloaded.record?.ownsSession, false)
        XCTAssertEqual(reloaded.evaluate(now: t0.addingTimeInterval(9999), enabled: true), .autoPause(at: t0.addingTimeInterval(600)))
        reloaded.clear()
        XCTAssertNil(reloaded.record)
    }

    func testUnsupportedSessionsGetNoRecordAndDisabledNeverActs() {
        XCTAssertNil(WatchCardioInactivityTracker.profile(type: .swim, isSwim: true, gps: false, heartRate: true))
        XCTAssertEqual(WatchCardioInactivityTracker.profile(type: .run, isSwim: false, gps: true, heartRate: true), .outdoor)
        XCTAssertEqual(WatchCardioInactivityTracker.profile(type: .cycle, isSwim: false, gps: false, heartRate: true), .indoor)
        XCTAssertEqual(WatchCardioInactivityTracker.profile(type: .other, isSwim: false, gps: false, heartRate: false), .timerOnly)
        let t = tracker()
        XCTAssertEqual(t.evaluate(now: t0.addingTimeInterval(99999), enabled: false), .none)
    }

    func testRecordCodableRoundTrip() throws {
        let r = WatchCardioInactivityRecord(type: .run, evidence: CardioActivityEvidence(lastUserActionAt: t0), startedAt: t0)
        let d = try JSONEncoder().encode(r)
        XCTAssertEqual(try JSONDecoder().decode(WatchCardioInactivityRecord.self, from: d), r)
    }
}
