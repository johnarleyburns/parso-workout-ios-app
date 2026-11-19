import Testing
import Foundation
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

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
@Suite final class PhoneCardioInactivityCoordinatorTests {
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

    @Test func outdoorAutoPausesThenEndsOnceAtDeadline() async {
        let (c, a, _) = make()
        await c.reconcile(now: at(599))
        #expect(a.pauses.isEmpty)
        await c.reconcile(now: at(600))
        #expect(a.pauses == [at(600)])
        #expect(c.session?.inactivity.pauseOrigin == .automatic)
        await c.reconcile(now: at(600 + 1799))
        #expect(a.finalizes.isEmpty)
        await c.reconcile(now: at(600 + 1800))
        await c.reconcile(now: at(99_999))
        await c.reconcile(now: at(199_999))
        #expect(a.pauses.count == 1)
        #expect(a.finalizes.count == 1)
        #expect(a.finalizes.first?.1 == at(2400))
        #expect(c.autoEndedReceipt != nil)
    }

    @Test func backgroundReconcileUsesOriginalDeadlineNotReturnTime() async {
        let (c, a, store) = make()
        // Relaunch: a new coordinator restored from the durable store.
        let restored = PhoneCardioInactivityCoordinator(store: store, actions: a)
        #expect(restored.session?.id == c.session?.id)
        await restored.reconcile(now: at(5 * 3600))
        #expect(a.finalizes.map(\.1) == [at(2400)])
        #expect(a.pauses == [at(600)])
    }

    @Test func distanceProgressExtendsButDuplicatesAndNoiseDoNot() async {
        let (c, a, _) = make()
        c.recordEvidence(.distance(totalMeters: 50), at: at(599))
        c.recordEvidence(.distance(totalMeters: 50), at: at(900))      // duplicate
        c.recordEvidence(.distance(totalMeters: 52), at: at(1000))     // noise
        c.recordEvidence(.passive(.duplicateLocationFix), at: at(1100))
        await c.reconcile(now: at(1198))
        #expect(a.pauses.isEmpty)
        await c.reconcile(now: at(1199))
        #expect(a.pauses == [at(1199)])
    }

    @Test func passiveEventsNeverCountAsActivity() async {
        let (c, a, _) = make()
        for p in CardioEvidenceEvent.PassiveSource.allCases { c.recordEvidence(.passive(p), at: at(500)) }
        await c.reconcile(now: at(600))
        #expect(a.pauses == [at(600)])
    }

    @Test func evidenceAfterDeadlineDoesNotRescue() async {
        let (c, a, _) = make()
        c.recordEvidence(.userAction, at: at(700)) // foreground wake-up after expiry
        await c.reconcile(now: at(700))
        #expect(a.pauses == [at(600)])
    }

    @Test func indoorHeartRateQualification() async {
        let (c, a, _) = make(profile: .indoor)
        c.recordEvidence(.heartRate(bpm: 130, sampleAt: at(500), restingHR: 60, maxHR: 185), at: at(500))
        c.recordEvidence(.heartRate(bpm: 130, sampleAt: at(500), restingHR: 60, maxHR: 185), at: at(900)) // replay/stale
        c.recordEvidence(.heartRate(bpm: 70, sampleAt: at(900), restingHR: 60, maxHR: 185), at: at(900))  // low
        c.recordEvidence(.distance(totalMeters: 500), at: at(900))                                         // ignored indoors
        await c.reconcile(now: at(1100))
        #expect(a.pauses == [at(1100)])
    }

    @Test func timerOnlyFallbackAutoPauses() async {
        let (c, a, _) = make(profile: .timerOnly)
        c.recordEvidence(.heartRate(bpm: 140, sampleAt: at(500), restingHR: nil, maxHR: nil), at: at(500))
        await c.reconcile(now: at(600))
        #expect(a.pauses == [at(600)])
    }

    @Test func manualPauseIsPreservedAndDisabledDoesNothing() async {
        let (c, a, _) = make()
        c.recordManualPause(at: at(100))
        await c.reconcile(now: at(100_000))
        #expect(a.pauses.isEmpty); #expect(a.finalizes.isEmpty)
        let (d, b, _) = make(enabled: false)
        await d.reconcile(now: at(100_000))
        #expect(b.pauses.isEmpty); #expect(b.finalizes.isEmpty)
    }

    @Test func resumeFromAutoPauseBeforeDeadlineAccountsPausedTime() async {
        let (c, a, _) = make()
        await c.reconcile(now: at(700))
        #expect(c.recordResume(at: at(1000)))
        #expect(c.session?.pausedAccumulated == 400)
        await c.reconcile(now: at(1500))
        #expect(a.pauses.count == 1)
        #expect(c.session?.activeDuration(endedAt: at(1500)) == 1100)
    }

    @Test func resumeRefusedAfterTerminalDeadline() async {
        let (c, _, _) = make()
        await c.reconcile(now: at(700))
        #expect(!c.recordResume(at: at(600 + 1800)))
    }

    @Test func activeDurationExcludesAutomaticPausedWindow() async {
        let (c, _, _) = make()
        await c.reconcile(now: at(10_000))
        #expect(c.session?.activeDuration(endedAt: at(2400)) == 600)
    }

    @Test func detachClearsStore() async {
        let (c, _, store) = make()
        c.detachTerminalSession()
        #expect(c.session == nil); #expect(store.stored == nil)
    }
}
