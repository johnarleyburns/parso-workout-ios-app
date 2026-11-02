import XCTest
import CadenceCore
@testable import CadenceFeatures

@MainActor
private final class FakeActions: PhoneCardioLifecycleActions {
    var pauses: [Date] = []
    var finalizes: [(UUID, Date)] = []
    func pauseForInactivity(session: PhoneLiveCardioSession, at: Date) { pauses.append(at) }
    func finalizePhoneCardio(sessionID: UUID, endedAt: Date, reason: PhoneCardioFinalizeReason) async {
        finalizes.append((sessionID, endedAt))
    }
}

@MainActor
final class PhoneCardioInactivityCoordinatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    private func make(profile: CardioSensorProfile = .outdoor, enabled: Bool = true)
        -> (PhoneCardioInactivityCoordinator, FakeActions, InMemoryPhoneLiveCardioStore) {
        let actions = FakeActions()
        let store = InMemoryPhoneLiveCardioStore()
        let c = PhoneCardioInactivityCoordinator(store: store, actions: actions)
        c.attach(session: PhoneLiveCardioSession(type: .run, route: "outdoor", start: t0,
                                                 sensorProfile: profile, autoPauseEnabled: enabled))
        return (c, actions, store)
    }

    func testOutdoorAutoPausesThenEndsOnceAtDeadline() async {
        let (c, a, _) = make()
        await c.reconcile(now: at(599))
        XCTAssertTrue(a.pauses.isEmpty)
        await c.reconcile(now: at(600))
        XCTAssertEqual(a.pauses, [at(600)])
        XCTAssertEqual(c.session?.inactivity.pauseOrigin, .automatic)
        await c.reconcile(now: at(600 + 1799))
        XCTAssertTrue(a.finalizes.isEmpty)
        await c.reconcile(now: at(600 + 1800))
        await c.reconcile(now: at(99_999))
        await c.reconcile(now: at(199_999))
        XCTAssertEqual(a.pauses.count, 1)
        XCTAssertEqual(a.finalizes.count, 1)
        XCTAssertEqual(a.finalizes.first?.1, at(2400))
        XCTAssertNotNil(c.autoEndedReceipt)
    }

    func testBackgroundReconcileUsesOriginalDeadlineNotReturnTime() async {
        let (c, a, store) = make()
        // Relaunch: a new coordinator restored from the durable store.
        let restored = PhoneCardioInactivityCoordinator(store: store, actions: a)
        XCTAssertEqual(restored.session?.id, c.session?.id)
        await restored.reconcile(now: at(5 * 3600))
        XCTAssertEqual(a.finalizes.map(\.1), [at(2400)])
        XCTAssertEqual(a.pauses, [at(600)])
    }

    func testDistanceProgressExtendsButDuplicatesAndNoiseDoNot() async {
        let (c, a, _) = make()
        c.recordEvidence(.distance(totalMeters: 50), at: at(599))
        c.recordEvidence(.distance(totalMeters: 50), at: at(900))      // duplicate
        c.recordEvidence(.distance(totalMeters: 52), at: at(1000))     // noise
        c.recordEvidence(.passive(.duplicateLocationFix), at: at(1100))
        await c.reconcile(now: at(1198))
        XCTAssertTrue(a.pauses.isEmpty)
        await c.reconcile(now: at(1199))
        XCTAssertEqual(a.pauses, [at(1199)])
    }

    func testPassiveEventsNeverCountAsActivity() async {
        let (c, a, _) = make()
        for p in CardioEvidenceEvent.PassiveSource.allCases { c.recordEvidence(.passive(p), at: at(500)) }
        await c.reconcile(now: at(600))
        XCTAssertEqual(a.pauses, [at(600)])
    }

    func testEvidenceAfterDeadlineDoesNotRescue() async {
        let (c, a, _) = make()
        c.recordEvidence(.userAction, at: at(700)) // foreground wake-up after expiry
        await c.reconcile(now: at(700))
        XCTAssertEqual(a.pauses, [at(600)])
    }

    func testIndoorHeartRateQualification() async {
        let (c, a, _) = make(profile: .indoor)
        c.recordEvidence(.heartRate(bpm: 130, sampleAt: at(500), restingHR: 60, maxHR: 185), at: at(500))
        c.recordEvidence(.heartRate(bpm: 130, sampleAt: at(500), restingHR: 60, maxHR: 185), at: at(900)) // replay/stale
        c.recordEvidence(.heartRate(bpm: 70, sampleAt: at(900), restingHR: 60, maxHR: 185), at: at(900))  // low
        c.recordEvidence(.distance(totalMeters: 500), at: at(900))                                         // ignored indoors
        await c.reconcile(now: at(1100))
        XCTAssertEqual(a.pauses, [at(1100)])
    }

    func testTimerOnlyFallbackAutoPauses() async {
        let (c, a, _) = make(profile: .timerOnly)
        c.recordEvidence(.heartRate(bpm: 140, sampleAt: at(500), restingHR: nil, maxHR: nil), at: at(500))
        await c.reconcile(now: at(600))
        XCTAssertEqual(a.pauses, [at(600)])
    }

    func testManualPauseIsPreservedAndDisabledDoesNothing() async {
        let (c, a, _) = make()
        c.recordManualPause(at: at(100))
        await c.reconcile(now: at(100_000))
        XCTAssertTrue(a.pauses.isEmpty); XCTAssertTrue(a.finalizes.isEmpty)
        let (d, b, _) = make(enabled: false)
        await d.reconcile(now: at(100_000))
        XCTAssertTrue(b.pauses.isEmpty); XCTAssertTrue(b.finalizes.isEmpty)
    }

    func testResumeFromAutoPauseBeforeDeadlineAccountsPausedTime() async {
        let (c, a, _) = make()
        await c.reconcile(now: at(700))
        XCTAssertTrue(c.recordResume(at: at(1000)))
        XCTAssertEqual(c.session?.pausedAccumulated, 400)
        await c.reconcile(now: at(1500))
        XCTAssertEqual(a.pauses.count, 1)
        XCTAssertEqual(c.session?.activeDuration(endedAt: at(1500)), 1100)
    }

    func testResumeRefusedAfterTerminalDeadline() async {
        let (c, _, _) = make()
        await c.reconcile(now: at(700))
        XCTAssertFalse(c.recordResume(at: at(600 + 1800)))
    }

    func testActiveDurationExcludesAutomaticPausedWindow() async {
        let (c, _, _) = make()
        await c.reconcile(now: at(10_000))
        XCTAssertEqual(c.session?.activeDuration(endedAt: at(2400)), 600)
    }

    func testDetachClearsStore() async {
        let (c, _, store) = make()
        c.detachTerminalSession()
        XCTAssertNil(c.session); XCTAssertNil(store.stored)
    }
}
