import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct WatchCardioInactivityTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func tracker(_ p: CardioSensorProfile = .outdoor, owns: Bool = true) -> WatchCardioInactivityTracker {
        let t = WatchCardioInactivityTracker(store: InMemoryWatchCardioInactivityStore())
        t.begin(type: .run, profile: p, ownsSession: owns, now: t0)
        return t
    }

    @Test func outdoorPausesAtTenMinutesAndEndsAfterGrace() {
        let t = tracker()
        #expect(t.evaluate(now: t0.addingTimeInterval(599), enabled: true) == .none)
        #expect(t.evaluate(now: t0.addingTimeInterval(600), enabled: true) == .autoPause(at: t0.addingTimeInterval(600)))
        t.recordAutoPause(at: t0.addingTimeInterval(600))
        #expect(t.evaluate(now: t0.addingTimeInterval(600 + 1799), enabled: true) == .none)
        #expect(t.evaluate(now: t0.addingTimeInterval(600 + 1800 + 5), enabled: true) ==
                       .autoEnd(at: t0.addingTimeInterval(2400)))
        // Duration excludes the automatic pause.
        #expect(t.record?.activeDuration(endedAt: t0.addingTimeInterval(2400)) == 600)
    }

    @Test func movingAtNineFiftyNineExtendsDeadline() {
        let t = tracker()
        #expect(t.recordEvidence(.distance(totalMeters: 50), at: t0.addingTimeInterval(599)))
        #expect(t.evaluate(now: t0.addingTimeInterval(600), enabled: true) == .none)
        #expect(t.record?.nextDeadline() == t0.addingTimeInterval(1199))
    }

    @Test func repeatedAndTinyDistanceDoNotExtend() {
        let t = tracker()
        #expect(t.recordEvidence(.distance(totalMeters: 50), at: t0.addingTimeInterval(100)))
        #expect(!t.recordEvidence(.distance(totalMeters: 50), at: t0.addingTimeInterval(500)))
        #expect(!t.recordEvidence(.distance(totalMeters: 54), at: t0.addingTimeInterval(500)))
        #expect(!t.recordEvidence(.passive(.watchRelayHeartbeat), at: t0.addingTimeInterval(500)))
    }

    @Test func indoorHeartRateQualificationAndStaleDuplicates() {
        let t = tracker(.indoor)
        let s = t0.addingTimeInterval(300)
        #expect(!t.recordEvidence(.distance(totalMeters: 500), at: s)) // distance ignored indoors? recorded but not counted
        #expect(t.recordEvidence(.heartRate(bpm: 130, sampleAt: s, restingHR: 60, maxHR: nil), at: s))
        // Duplicate sample, stale sample, low HR do not extend.
        #expect(!t.recordEvidence(.heartRate(bpm: 130, sampleAt: s, restingHR: 60, maxHR: nil), at: s.addingTimeInterval(10)))
        #expect(!t.recordEvidence(.heartRate(bpm: 140, sampleAt: s.addingTimeInterval(1), restingHR: nil, maxHR: nil),
                                        at: s.addingTimeInterval(500)))
        #expect(!t.recordEvidence(.heartRate(bpm: 70, sampleAt: s.addingTimeInterval(20), restingHR: 60, maxHR: nil),
                                        at: s.addingTimeInterval(20)))
        #expect(t.record?.nextDeadline() == s.addingTimeInterval(600))
    }

    @Test func userResumePreventsTerminalEndAndManualPauseNeverEnds() {
        let t = tracker()
        t.recordAutoPause(at: t0.addingTimeInterval(600))
        #expect(t.recordResume(at: t0.addingTimeInterval(1000)))
        #expect(t.evaluate(now: t0.addingTimeInterval(5000), enabled: true) ==
                       .autoPause(at: t0.addingTimeInterval(1600)))
        #expect(t.record?.pausedAccumulated == 400)

        let m = tracker()
        m.recordManualPause(at: t0.addingTimeInterval(60))
        #expect(m.evaluate(now: t0.addingTimeInterval(100_000), enabled: true) == .none)
    }

    @Test func resumeRefusedAfterTerminalDeadline() {
        let t = tracker()
        t.recordAutoPause(at: t0.addingTimeInterval(600))
        #expect(!t.recordResume(at: t0.addingTimeInterval(2500)))
        #expect(t.evaluate(now: t0.addingTimeInterval(2500), enabled: true) == .autoEnd(at: t0.addingTimeInterval(2400)))
    }

    @Test func relaunchRecoveryUsesDurableRecordAndLayeredOwnership() {
        let store = InMemoryWatchCardioInactivityStore()
        WatchCardioInactivityTracker(store: store).begin(type: .run, profile: .outdoor, ownsSession: false, now: t0)
        let reloaded = WatchCardioInactivityTracker(store: store)
        #expect(reloaded.record?.ownsSession == false)
        #expect(reloaded.evaluate(now: t0.addingTimeInterval(9999), enabled: true) == .autoPause(at: t0.addingTimeInterval(600)))
        reloaded.clear()
        #expect(reloaded.record == nil)
    }

    @Test func unsupportedSessionsGetNoRecordAndDisabledNeverActs() {
        #expect(WatchCardioInactivityTracker.profile(type: .swim, isSwim: true, gps: false, heartRate: true) == nil)
        #expect(WatchCardioInactivityTracker.profile(type: .run, isSwim: false, gps: true, heartRate: true) == .outdoor)
        #expect(WatchCardioInactivityTracker.profile(type: .cycle, isSwim: false, gps: false, heartRate: true) == .indoor)
        #expect(WatchCardioInactivityTracker.profile(type: .other, isSwim: false, gps: false, heartRate: false) == .timerOnly)
        let t = tracker()
        #expect(t.evaluate(now: t0.addingTimeInterval(99999), enabled: false) == .none)
    }

    @Test func recordCodableRoundTrip() throws {
        let r = WatchCardioInactivityRecord(type: .run, evidence: CardioActivityEvidence(lastUserActionAt: t0), startedAt: t0)
        let d = try JSONEncoder().encode(r)
        #expect(try JSONDecoder().decode(WatchCardioInactivityRecord.self, from: d) == r)
    }
}
