import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

// MARK: - Test doubles (fake clock/transport/HK/recorder; no sleeps, no HealthKit, no Watch)

/// Phone recorder + Health-backup boundary. Records the real pause/save side effects so
/// tests prove the recorder paused, not just that UI state changed.
@MainActor
private final class FakePhoneCardioPlatform: PhoneCardioLifecycleActions {
    var recorderPaused = false
    var pauses: [Date] = []
    var saves: [(id: UUID, endedAt: Date, activeDuration: TimeInterval)] = []
    var healthBackups = 0
    var log: [String] = []
    weak var coordinator: PhoneCardioInactivityCoordinator?

    func pauseForInactivity(session: PhoneLiveCardioSession, at: Date) {
        recorderPaused = true; pauses.append(at); log.append("recorder.pause@\(Int(at.timeIntervalSince1970))")
    }
    func finalizePhoneCardio(sessionID: UUID, endedAt: Date, reason: PhoneCardioFinalizeReason) async {
        let active = coordinator?.session?.activeDuration(endedAt: endedAt) ?? -1
        saves.append((sessionID, endedAt, active))
        healthBackups += 1
        log.append("save+healthBackup@\(Int(endedAt.timeIntervalSince1970)) reason=\(reason.rawValue)")
    }
}

/// Watch-side owner mirroring `WatchWorkoutManager+CardioInactivity`: the durable record is the
/// only source of truth; a fake `HKWorkoutSession` and WatchConnectivity outbox record effects.
private final class FakeWatchCardioOwner {
    let tracker: WatchCardioInactivityTracker
    var hkPaused = false
    var hkEnds = 0
    var outbox: [WatchCardioCompletion] = []
    var notices: [WatchCardioInactivityNotice] = []
    var activeDurations: [TimeInterval] = []
    var log: [String] = []
    var enabled = true

    init(store: WatchCardioInactivityStoring) { tracker = WatchCardioInactivityTracker(store: store) }

    /// Screen-off recovery, HK callbacks and the armed deadline task all call this.
    func reconcile(now: Date) {
        guard let record = tracker.record else { return }
        switch tracker.evaluate(now: now, enabled: enabled) {
        case .autoPause(let at):
            if record.ownsSession { hkPaused = true }
            tracker.recordAutoPause(at: at)
            log.append("pause@\(Int(at.timeIntervalSince1970))")
            reconcile(now: now)
        case .autoEnd(let at):
            activeDurations.append(record.activeDuration(endedAt: at))
            if record.ownsSession { hkEnds += 1; log.append("hk.end") }
            outbox.append(WatchCardioCompletion(id: record.sessionGeneration, type: record.type,
                                                start: record.startedAt, end: at))
            notices.append(WatchCardioInactivityNotice(type: record.type, endedAt: at))
            tracker.clear()
            log.append("outbox@\(Int(at.timeIntervalSince1970))")
        case .none:
            return
        }
    }

    /// Natural completion: user/plan finished before any deadline.
    func completeNaturally(at: Date) {
        guard let record = tracker.record else { return }
        if record.ownsSession { hkEnds += 1 }
        outbox.append(WatchCardioCompletion(id: record.sessionGeneration, type: record.type,
                                            start: record.startedAt, end: at))
        tracker.clear()
    }
}

@MainActor
final class CardioInactivityRegressionSuite: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var clock: ManualInactivityClock!
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    override func setUp() { clock = ManualInactivityClock(t0) }

    private func phone(profile: CardioSensorProfile = .outdoor, enabled: Bool = true,
                       store: InMemoryPhoneLiveCardioStore = InMemoryPhoneLiveCardioStore())
        -> (PhoneCardioInactivityCoordinator, FakePhoneCardioPlatform, InMemoryPhoneLiveCardioStore) {
        let platform = FakePhoneCardioPlatform()
        let c = PhoneCardioInactivityCoordinator(store: store, actions: platform)
        platform.coordinator = c
        c.attach(session: PhoneLiveCardioSession(type: .run, route: "outdoor", start: t0,
                                                 sensorProfile: profile, autoPauseEnabled: enabled))
        return (c, platform, store)
    }

    private func watch(profile: CardioSensorProfile = .outdoor, type: CardioType = .run, owns: Bool = true,
                       store: WatchCardioInactivityStoring = InMemoryWatchCardioInactivityStore()) -> FakeWatchCardioOwner {
        let o = FakeWatchCardioOwner(store: store)
        o.tracker.begin(type: type, profile: profile, ownsSession: owns, now: t0)
        return o
    }

    private func intervalRunner(started: Bool) throws -> CombinedPlanRunner {
        let plan = try CombinedExecutionPlan(session: Session(title: "Intervals", items: [
            .cardio(CardioItem(id: UUID(), order: 0,
                               prescription: .steadyState(SteadyState(activity: .run, durationSeconds: 3600))))
        ]))
        let r = CombinedPlanRunner(plan: plan)
        if started { r.start(now: t0) }
        return r
    }

    private func intervalDecision(_ r: CombinedPlanRunner, state: CardioInactivityState = CardioInactivityState(),
                                  enabled: Bool = true, now: Date) -> CardioInactivityDecision {
        let e = IntervalInactivityEvidenceAdapter.evidence(
            runner: r, lastUserActionAt: t0, lastSensorEvidenceAt: nil,
            pauseOrigin: state.pauseOrigin, autoPausedAt: state.pauseOrigin == .automatic ? state.pausedAt : nil)
        return CardioInactivityPolicy.decide(evidence: e, now: now, enabled: enabled)
    }

    // MARK: Required matrix

    func testOutdoorCardioAutoPausesAfterTenMinutesWithoutEvidence() async {
        let (c, p, _) = phone()
        await c.reconcile(now: at(599))
        XCTAssertFalse(p.recorderPaused, "phone recorder: must not pause at 9:59")
        await c.reconcile(now: at(600))
        XCTAssertTrue(p.recorderPaused, "phone recorder: must actually pause")
        XCTAssertEqual(p.pauses, [at(600)], "phone policy: exact deadline timestamp")
        XCTAssertEqual(c.session?.inactivity.pauseOrigin, .automatic)
        XCTAssertEqual(c.session?.inactivity.autoEndDeadline, at(2400))
        XCTAssertTrue(p.saves.isEmpty)
        // Watch mirror.
        let w = watch()
        w.reconcile(now: at(599)); XCTAssertFalse(w.hkPaused)
        w.reconcile(now: at(600))
        XCTAssertTrue(w.hkPaused, "watch HKWorkoutSession: must actually pause")
        XCTAssertEqual(w.tracker.record?.autoPausedAt, at(600))
        XCTAssertEqual(w.tracker.record?.pauseOrigin, .automatic)
    }

    func testOutdoorMovementAtNineFiftyNineExtendsDeadline() async {
        let (c, p, _) = phone()
        c.recordEvidence(.distance(totalMeters: 50), at: at(599))
        await c.reconcile(now: at(600))
        await c.reconcile(now: at(1198))
        XCTAssertTrue(p.pauses.isEmpty, "phone: movement evidence must prevent a false pause")
        await c.reconcile(now: at(1199))
        XCTAssertEqual(p.pauses, [at(1199)])
        let w = watch()
        XCTAssertTrue(w.tracker.recordEvidence(.distance(totalMeters: 50), at: at(599)))
        w.reconcile(now: at(1198)); XCTAssertFalse(w.hkPaused)
        XCTAssertEqual(w.tracker.record?.nextDeadline(), at(1199))
    }

    func testIndoorQualifyingHRExtendsButStaleHeartbeatDoesNot() async {
        let (c, p, _) = phone(profile: .indoor)
        c.recordEvidence(.heartRate(bpm: 130, sampleAt: at(500), restingHR: 60, maxHR: 185), at: at(500))
        // Stale sample (received 200 s after it was taken) and relay heartbeat are not evidence.
        c.recordEvidence(.heartRate(bpm: 140, sampleAt: at(600), restingHR: 60, maxHR: 185), at: at(800))
        c.recordEvidence(.passive(.watchRelayHeartbeat), at: at(900))
        c.recordEvidence(.passive(.heartRateReceiptOnly), at: at(1000))
        await c.reconcile(now: at(1099)); XCTAssertTrue(p.pauses.isEmpty)
        await c.reconcile(now: at(1100)); XCTAssertEqual(p.pauses, [at(1100)])
        let w = watch(profile: .indoor, type: .cycle)
        XCTAssertTrue(w.tracker.recordEvidence(.heartRate(bpm: 130, sampleAt: at(500), restingHR: 60, maxHR: nil), at: at(500)))
        XCTAssertFalse(w.tracker.recordEvidence(.heartRate(bpm: 140, sampleAt: at(600), restingHR: 60, maxHR: nil), at: at(800)))
        XCTAssertFalse(w.tracker.recordEvidence(.passive(.watchRelayHeartbeat), at: at(900)))
        w.reconcile(now: at(1100))
        XCTAssertEqual(w.tracker.record?.autoPausedAt, at(1100))
    }

    func testAutoPausedCardioEndsAfterGraceAtFixedDeadline() async {
        let (c, p, store) = phone()
        await c.reconcile(now: at(600))
        await c.reconcile(now: at(600 + 1799)); XCTAssertTrue(p.saves.isEmpty)
        await c.reconcile(now: at(50_000)) // observed hours late
        await c.reconcile(now: at(60_000))
        XCTAssertEqual(p.saves.count, 1, "phone: exactly one save/end")
        XCTAssertEqual(p.healthBackups, 1, "phone: exactly one Health backup")
        XCTAssertEqual(p.saves.first?.endedAt, at(2400), "phone: fixed terminal deadline, not observation time")
        XCTAssertEqual(p.saves.first?.activeDuration, 600, "phone: automatic pause excluded")
        XCTAssertEqual(c.session?.receipt?.reason, .inactivity)
        XCTAssertEqual(c.session?.inactivity.autoEndReason, CardioInactivityState.autoEndReasonText)
        XCTAssertFalse(CardioInactivityState.autoEndReasonText.isEmpty, "accessible notice text")
        XCTAssertNotNil(c.autoEndedReceipt)
        XCTAssertFalse(c.recordResume(at: at(60_000)), "no resume after terminal")
        // After the user acknowledges, nothing remains to restore.
        c.detachTerminalSession()
        XCTAssertNil(store.stored)
        XCTAssertNil(PhoneCardioInactivityCoordinator(store: store).session)
        // Watch mirror.
        let w = watch()
        w.reconcile(now: at(50_000)); w.reconcile(now: at(60_000))
        XCTAssertEqual(w.outbox.count, 1); XCTAssertEqual(w.hkEnds, 1)
        XCTAssertEqual(w.outbox.first?.end, at(2400))
        XCTAssertEqual(w.activeDurations, [600])
        XCTAssertEqual(w.notices, [WatchCardioInactivityNotice(type: .run, endedAt: at(2400))])
        XCTAssertNil(w.tracker.record, "watch: no resume state remains")
    }

    func testManualPauseNeverAutoEnds() async {
        let (c, p, _) = phone()
        c.recordManualPause(at: at(100))
        await c.reconcile(now: at(100 + 24 * 3600))
        XCTAssertTrue(p.pauses.isEmpty); XCTAssertTrue(p.saves.isEmpty)
        XCTAssertEqual(c.session?.inactivity.pauseOrigin, .manual)
        let w = watch()
        w.tracker.recordManualPause(at: at(100))
        w.reconcile(now: at(100 + 24 * 3600))
        XCTAssertTrue(w.outbox.isEmpty); XCTAssertEqual(w.hkEnds, 0)
        XCTAssertNotNil(w.tracker.record)
        let r = try? intervalRunner(started: true)
        r?.pause()
        let manual = intervalDecision(r!, state: CardioInactivityState(pauseOrigin: .manual, pausedAt: at(100)),
                                      now: at(24 * 3600))
        XCTAssertEqual(manual, .continuePaused)
    }

    func testPhoneCardioBackgroundRelaunchUsesOriginalDeadlines() async {
        let (c, p, store) = phone()
        c.recordEvidence(.distance(totalMeters: 100), at: at(120))
        // Process suspended/killed; relaunch hours later restores from the durable store.
        let relaunchPlatform = FakePhoneCardioPlatform()
        let restored = PhoneCardioInactivityCoordinator(store: store, actions: relaunchPlatform)
        relaunchPlatform.coordinator = restored
        XCTAssertEqual(restored.session?.id, c.session?.id)
        await restored.reconcile(now: at(5 * 3600))
        XCTAssertEqual(relaunchPlatform.pauses, [at(720)], "pause deadline = last evidence + 10 min")
        XCTAssertEqual(relaunchPlatform.saves.map(\.endedAt), [at(720 + 1800)])
        XCTAssertEqual(relaunchPlatform.saves.first?.activeDuration, 720)
        XCTAssertEqual(relaunchPlatform.log, ["recorder.pause@\(Int(at(720).timeIntervalSince1970))",
                                              "save+healthBackup@\(Int(at(2520).timeIntervalSince1970)) reason=inactivity"],
                       "event order: pause before save")
        // A second relaunch after finalize must not repeat the terminal operation.
        let again = FakePhoneCardioPlatform()
        let third = PhoneCardioInactivityCoordinator(store: store, actions: again)
        again.coordinator = third
        await third.reconcile(now: at(9 * 3600))
        XCTAssertTrue(again.saves.isEmpty); XCTAssertTrue(again.pauses.isEmpty)
        XCTAssertTrue(p.saves.isEmpty, "original process did nothing")
    }

    func testWatchCardioScreenOffRecoveryFinishesOverdueSessionOnce() {
        let store = InMemoryWatchCardioInactivityStore()
        _ = watch(store: store)
        // Process torn down with the screen off; a fresh owner recovers from the durable record.
        let recovered = FakeWatchCardioOwner(store: store)
        recovered.reconcile(now: at(4 * 3600))
        recovered.reconcile(now: at(4 * 3600 + 1))
        XCTAssertEqual(recovered.log, ["pause@\(Int(at(600).timeIntervalSince1970))", "hk.end",
                                       "outbox@\(Int(at(2400).timeIntervalSince1970))"], "watch event order")
        XCTAssertEqual(recovered.hkEnds, 1)
        XCTAssertEqual(recovered.outbox.count, 1)
        XCTAssertEqual(recovered.outbox.first?.end, at(2400))
        XCTAssertEqual(recovered.activeDurations, [600])
        XCTAssertEqual(recovered.notices.count, 1)
        XCTAssertNil(FakeWatchCardioOwner(store: store).tracker.record, "no resume state after relaunch")
    }

    func testLayeredWatchCardioExpiryDoesNotEndPhoneStrength() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let s = WorkoutSession(title: "Push", date: t0)
        ctx.insert(s)
        ctx.insert(SetEntry(weight: 80, reps: 5, order: 0, completedAt: t0, session: s))
        let m = ActiveWorkoutModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertTrue(m.startStrength(s, now: t0))
        var strengthFinalized = 0
        m.strengthFinalizer = { _, _ in strengthFinalized += 1 }
        m.recordMeaningfulActivity(.setMutation, now: at(2390)) // lifter is active on the phone

        let w = watch(owns: false) // layered over phone strength: does not own the HKWorkoutSession
        w.reconcile(now: at(2400))
        XCTAssertEqual(w.outbox.count, 1, "layered cardio layer still ends and reports")
        XCTAssertEqual(w.hkEnds, 0, "layered cardio must not end the phone-owned HK session")
        XCTAssertFalse(w.hkPaused)
        clock.set(at(2400))
        XCTAssertNil(m.reconcileStrengthInactivity(enabled: true, timeoutMinutes: 10, clock: clock))
        XCTAssertTrue(m.isActive, "phone strength must remain active")
        XCTAssertEqual(strengthFinalized, 0)
        XCTAssertNil(s.endedAt)
    }

    func testPlannedIntervalRestDoesNotCountAsInactivity() throws {
        let running = try intervalRunner(started: true)
        XCTAssertEqual(intervalDecision(running, now: at(3 * 3600)), .continueRunning,
                       "interval: a running plan phase (work or rest) never pauses")
        let rest = CardioActivityEvidence(lastUserActionAt: t0, isInPlannedIntervalPhase: true, sensorProfile: .timerOnly)
        XCTAssertEqual(CardioInactivityPolicy.decide(evidence: rest, now: at(3 * 3600), enabled: true), .continueRunning)
        let finished = try intervalRunner(started: true)
        finished.finish(now: at(100))
        XCTAssertEqual(intervalDecision(finished, now: at(3 * 3600)), .continueRunning)
    }

    func testStalledPhoneIntervalAutoPausesAndEnds() async throws {
        let stalled = try intervalRunner(started: false)
        XCTAssertEqual(intervalDecision(stalled, now: at(599)), .continueRunning)
        XCTAssertEqual(intervalDecision(stalled, now: at(600)), .autoPause(at: at(600)))
        var state = CardioInactivityState()
        state.recordAutoPause(at: at(600))
        XCTAssertEqual(intervalDecision(stalled, state: state, now: at(2399)), .continuePaused)
        XCTAssertEqual(intervalDecision(stalled, state: state, now: at(99_999)), .autoEnd(at: at(2400)))
        // The phone coordinator drives the same lifecycle for interval cardio sessions.
        let (c, p, _) = phone(profile: .timerOnly)
        await c.reconcile(now: at(99_999)); await c.reconcile(now: at(199_999))
        XCTAssertEqual(p.pauses, [at(600)]); XCTAssertTrue(p.recorderPaused)
        XCTAssertEqual(p.saves.map(\.endedAt), [at(2400)]); XCTAssertEqual(p.saves.first?.activeDuration, 600)
    }

    func testStalledWatchIntervalAutoPausesAndEnds() {
        let w = watch(profile: .timerOnly, type: .hiit)
        w.reconcile(now: at(600)); XCTAssertTrue(w.hkPaused); XCTAssertEqual(w.hkEnds, 0)
        w.reconcile(now: at(99_999)); w.reconcile(now: at(199_999))
        XCTAssertEqual(w.outbox.count, 1); XCTAssertEqual(w.hkEnds, 1)
        XCTAssertEqual(w.outbox.first?.type, .hiit)
        XCTAssertEqual(w.outbox.first?.end, at(2400)); XCTAssertEqual(w.activeDurations, [600])
        XCTAssertNil(w.tracker.record)
    }

    func testNaturalIntervalCompletionWinsRaceAgainstTimeout() throws {
        // Watch: natural completion at 9:59 clears the durable record before the deadline task fires.
        let w = watch(profile: .timerOnly, type: .hiit)
        w.completeNaturally(at: at(599))
        w.reconcile(now: at(600)); w.reconcile(now: at(5 * 3600))
        XCTAssertEqual(w.outbox.count, 1); XCTAssertEqual(w.outbox.first?.end, at(599))
        XCTAssertEqual(w.hkEnds, 1); XCTAssertTrue(w.notices.isEmpty, "no inactivity notice for a natural finish")
        // Phone: a finished runner is never inactive, regardless of when the timeout "fires".
        let r = try intervalRunner(started: true)
        r.finish(now: at(599))
        XCTAssertTrue(r.isComplete)
        XCTAssertEqual(intervalDecision(r, now: at(600)), .continueRunning)
    }

    func testCardioCompletionDuplicatesImportExactlyOnce() throws {
        let w = watch()
        w.reconcile(now: at(3 * 3600))
        let completion = try XCTUnwrap(w.outbox.first)
        // Fake WatchConnectivity: duplicated + reordered delivery of the same envelope.
        var transport = FakeWatchTransport()
        let payload = try completion.encoded()
        transport.send(["cardioCompletion": payload], copies: 3)
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        var inserted = 0
        for packet in transport.delivered {
            let decoded = try WatchCardioCompletion.decode(try XCTUnwrap(packet["cardioCompletion"] as? Data))
            if try WorkoutRepository.ingest(decoded, in: ctx) { inserted += 1 }
        }
        XCTAssertEqual(inserted, 1, "phone import: duplicates must be harmless")
        XCTAssertEqual(try WorkoutRepository.allCardio(ctx).count, 1)
        // A later HealthKit import of the same workout reconciles instead of duplicating.
        let hk = IngestedWorkout(id: UUID(), type: .run, start: completion.start, end: completion.end, importedKind: .running)
        XCTAssertEqual(try WorkoutRepository.ingest([hk], in: ctx), 0)
        let all = try WorkoutRepository.allCardio(ctx)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.healthKitWorkoutUUID, hk.id)
    }

    func testDisabledAutoPauseDoesNothingForEachModality() async throws {
        for profile in [CardioSensorProfile.outdoor, .indoor, .timerOnly] {
            let (c, p, _) = phone(profile: profile, enabled: false)
            await c.reconcile(now: at(48 * 3600))
            XCTAssertTrue(p.pauses.isEmpty && p.saves.isEmpty, "phone \(profile) with auto-pause off must not act")
            XCTAssertFalse(p.recorderPaused)
            let w = watch(profile: profile)
            w.enabled = false
            w.reconcile(now: at(48 * 3600))
            XCTAssertFalse(w.hkPaused, "watch \(profile)"); XCTAssertTrue(w.outbox.isEmpty)
            XCTAssertNotNil(w.tracker.record)
        }
        let stalled = try intervalRunner(started: false)
        XCTAssertEqual(intervalDecision(stalled, enabled: false, now: at(48 * 3600)), .continueRunning, "interval")
    }
}
