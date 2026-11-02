import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

// MARK: - Test doubles (metadata/outcome names only; no user data)

/// Manual clock: advances instantly; `sleep(until:)` jumps time forward and records the call.
final class ManualInactivityClock: WorkoutInactivityClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private(set) var sleeps: [Date] = []
    init(_ start: Date) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
    func set(_ date: Date) { lock.withLock { current = date } }
    func sleep(until: Date) async throws {
        lock.withLock { sleeps.append(until); if until > current { current = until } }
    }
}

/// Records every lifecycle call by outcome name so failures say which layer regressed.
final class InactivityDiagnostics {
    private(set) var events: [String] = []
    func record(_ name: String) { events.append(name) }
    func count(_ name: String) -> Int { events.filter { $0 == name }.count }
}

/// Fake Watch transport: dedups by completion id, supports reorder/duplication of packets.
struct FakeWatchTransport {
    var delivered: [[String: Any]] = []
    mutating func send(_ p: [String: Any], copies: Int = 1) { for _ in 0..<copies { delivered.append(p) } }
}

/// Fake HKWorkoutSession / Live Activity boundary.
final class FakeWorkoutPlatform {
    let diag: InactivityDiagnostics
    init(_ d: InactivityDiagnostics) { diag = d }
    func endHKSession() { diag.record("hk.end") }
    func endLiveActivity() { diag.record("liveActivity.end") }
}

@MainActor
final class StrengthInactivityRegressionSuite: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let timeout = 10
    private var clock: ManualInactivityClock!
    private var diag: InactivityDiagnostics!

    override func setUp() {
        clock = ManualInactivityClock(t0)
        diag = InactivityDiagnostics()
    }

    private func phone(withSet: Bool = true) throws -> (ActiveWorkoutModel, WorkoutSession, ModelContext) {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let s = WorkoutSession(title: "Push", date: t0)
        ctx.insert(s)
        if withSet { ctx.insert(SetEntry(weight: 80, reps: 5, order: 0, completedAt: t0, session: s)) }
        let m = ActiveWorkoutModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertTrue(m.startStrength(s, now: t0))
        let platform = FakeWorkoutPlatform(diag)
        m.strengthFinalizer = { _, _ in platform.endHKSession(); platform.endLiveActivity(); self.diag.record("finalizer") }
        return (m, s, ctx)
    }

    private func reconcile(_ m: ActiveWorkoutModel, enabled: Bool = true) -> FinalizeResult? {
        m.reconcileStrengthInactivity(enabled: enabled, timeoutMinutes: timeout, clock: clock)
    }

    private func watchTracker() -> WatchStrengthInactivityTracker {
        WatchStrengthInactivityTracker(store: .init(suiteName: "regression.\(UUID().uuidString)"))
    }

    private func assertTerminalPhone(_ m: ActiveWorkoutModel, _ s: WorkoutSession, deadline: Date,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.endedAt, deadline, "policy: endedAt must be the deadline", file: file, line: line)
        XCTAssertEqual(s.endReasonRaw, "inactivity", file: file, line: line)
        XCTAssertEqual(s.orderedSets.count, 1, "policy: sets must survive", file: file, line: line)
        XCTAssertFalse(m.isActive, "phone ownership: model still active", file: file, line: line)
        XCTAssertNil(m.presentedSurface, file: file, line: line)
        XCTAssertEqual(diag.count("hk.end"), 1, file: file, line: line)
        XCTAssertEqual(diag.count("liveActivity.end"), 1, file: file, line: line)
        XCTAssertEqual(m.inactivityNotice?.endedAt, deadline, "notice must be reachable", file: file, line: line)
        XCTAssertEqual(m.inactivityNotice?.message, "Ended after 10 minutes inactive", file: file, line: line)
    }

    // MARK: Required matrix

    func testPhoneStrengthEndsExactlyAtTenMinuteDeadline() throws {
        let (m, s, _) = try phone()
        clock.set(t0.addingTimeInterval(599))
        XCTAssertNil(reconcile(m)); XCTAssertTrue(m.isActive)
        clock.set(t0.addingTimeInterval(600))
        XCTAssertEqual(reconcile(m), .finalized)
        assertTerminalPhone(m, s, deadline: t0.addingTimeInterval(600))
        XCTAssertNil(reconcile(m), "repeat reconcile is a no-op")
        XCTAssertEqual(diag.count("finalizer"), 1)
    }

    func testWatchStrengthEndsExactlyAtTenMinuteDeadline() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let s = WorkoutSession(title: "Push", date: t0)
        ctx.insert(s)
        ctx.insert(SetEntry(weight: 80, reps: 5, order: 0, completedAt: t0, session: s))
        let tracker = watchTracker()
        tracker.begin(sessionID: s.id, now: clock.now, timeoutMinutes: timeout, enabled: true)
        clock.set(t0.addingTimeInterval(599))
        XCTAssertEqual(tracker.evaluate(now: clock.now, enabled: true), .waiting(until: t0.addingTimeInterval(600)))
        clock.set(t0.addingTimeInterval(600))
        guard case let .finalize(record, endedAt) = tracker.evaluate(now: clock.now, enabled: true) else {
            return XCTFail("watch watchdog: deadline must finalize")
        }
        XCTAssertEqual(WatchStrengthInactivityFinalizer.finalize(sessionID: record.sessionID, endedAt: endedAt,
                                                                 now: clock.now, context: ctx), .finalized)
        tracker.clear(matching: record.sessionGeneration)
        XCTAssertEqual(s.endedAt, t0.addingTimeInterval(600))
        XCTAssertEqual(s.endReasonRaw, "inactivity")
        XCTAssertEqual(s.orderedSets.count, 1)
        XCTAssertNil(tracker.record, "persistent watchdog record cleared")
        XCTAssertEqual(WatchStrengthInactivityFinalizer.finalize(sessionID: s.id, endedAt: endedAt,
                                                                 now: clock.now, context: ctx), .alreadyEnded)
        XCTAssertEqual(WatchStrengthInactivityNotice(sessionID: s.id, endedAt: endedAt, timeoutMinutes: 10,
                                                     keptSets: true).message,
                       "Workout ended after 10 minutes inactive")
    }

    func testSetAtNineMinutesFiftyNineSecondsResetsDeadline() throws {
        let (m, s, _) = try phone()
        clock.set(t0.addingTimeInterval(599))
        m.recordMeaningfulActivity(.setMutation, now: clock.now)
        clock.set(t0.addingTimeInterval(599 + 599))
        XCTAssertNil(reconcile(m)); XCTAssertTrue(m.isActive)
        clock.advance(1)
        XCTAssertEqual(reconcile(m), .finalized)
        XCTAssertEqual(s.endedAt, t0.addingTimeInterval(599 + 600))
        // Watch side
        let tracker = watchTracker()
        tracker.begin(sessionID: UUID(), now: t0, timeoutMinutes: timeout, enabled: true)
        let r = tracker.recordActivity(.setMutation, now: t0.addingTimeInterval(599))
        XCTAssertEqual(r?.deadline, t0.addingTimeInterval(1199))
    }

    func testBackgroundedPhoneReconcilesToOriginalDeadlineOnReturn() throws {
        let (m, s, _) = try phone()
        m.writeHeartbeat(now: t0.addingTimeInterval(30)) // last sign of life before suspension
        clock.set(t0.addingTimeInterval(4 * 3600))       // user returns hours later
        XCTAssertEqual(reconcile(m), .finalized)
        assertTerminalPhone(m, s, deadline: t0.addingTimeInterval(600))
        XCTAssertEqual(s.inactivityAutoEndedAt, clock.now, "reconciliation time is recorded separately")
    }

    func testRelaunchedWatchFinalizesOverduePersistedSession() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let s = WorkoutSession(title: "Legs", date: t0)
        ctx.insert(s)
        ctx.insert(SetEntry(weight: 100, reps: 5, order: 0, completedAt: t0, session: s))
        let suite = "regression.relaunch.\(UUID().uuidString)"
        WatchStrengthInactivityTracker(store: .init(suiteName: suite))
            .begin(sessionID: s.id, now: t0, timeoutMinutes: timeout, enabled: true)
        // "Relaunch": brand-new tracker over the same durable store.
        let relaunched = WatchStrengthInactivityTracker(store: .init(suiteName: suite))
        clock.set(t0.addingTimeInterval(3 * 3600))
        guard case let .finalize(rec, endedAt) = relaunched.evaluate(now: clock.now, enabled: true) else {
            return XCTFail("watch watchdog: persisted overdue record must finalize")
        }
        XCTAssertEqual(endedAt, t0.addingTimeInterval(600))
        XCTAssertEqual(WatchStrengthInactivityFinalizer.finalize(sessionID: rec.sessionID, endedAt: endedAt,
                                                                 now: clock.now, context: ctx), .finalized)
        XCTAssertEqual(s.endedAt, t0.addingTimeInterval(600))
        XCTAssertEqual(s.orderedSets.count, 1)
    }

    func testPassiveHeartRateAndScreenWakeDoNotResetDeadline() throws {
        let (m, s, _) = try phone()
        for p in StrengthPassiveEvent.allCases {
            var st = StrengthInactivityPolicy.State(lastMeaningfulActivityAt: t0)
            st.record(p, at: t0.addingTimeInterval(500))
            XCTAssertEqual(st.lastMeaningfulActivityAt, t0, "policy: \(p) must be passive")
        }
        m.writeHeartbeat(now: t0.addingTimeInterval(500))
        let tracker = watchTracker()
        tracker.begin(sessionID: UUID(), now: t0, timeoutMinutes: timeout, enabled: true)
        _ = tracker.evaluate(now: t0.addingTimeInterval(500), enabled: true)
        XCTAssertEqual(tracker.record?.lastMeaningfulActivityAt, t0)
        clock.set(t0.addingTimeInterval(600))
        XCTAssertEqual(reconcile(m), .finalized)
        XCTAssertEqual(s.endedAt, t0.addingTimeInterval(600))
    }

    func testDisabledAutoEndNeverFinalizes() throws {
        let (m, _, _) = try phone()
        clock.set(t0.addingTimeInterval(10 * 3600))
        XCTAssertNil(reconcile(m, enabled: false)); XCTAssertTrue(m.isActive)
        let tracker = watchTracker()
        XCTAssertNil(tracker.begin(sessionID: UUID(), now: t0, timeoutMinutes: timeout, enabled: false))
        XCTAssertEqual(tracker.evaluate(now: clock.now, enabled: false), .noRecord)
        XCTAssertEqual(diag.count("finalizer"), 0)
    }

    func testCardioIntervalSwimAndMonitoringAreNotAutoEnded() {
        for t in WorkoutType.allCases where t != .weights {
            XCTAssertFalse(StrengthInactivityPolicy.applies(to: t), "policy: \(t) must not auto-end")
        }
        XCTAssertTrue(StrengthInactivityPolicy.applies(to: .weights))
        for c in CardioType.allCases {
            XCTAssertFalse(StrengthInactivityPolicy.applies(to: c), "policy: \(c) must not auto-end")
        }
    }

    func testPhoneAndWatchRaceToExpireProducesOneTerminalCompletion() throws {
        let (m, s, ctx) = try phone()
        let route = WatchStrengthCompletionRoute(sessionID: s.id, transferID: UUID(), captureEpoch: UUID())
        let cid = UUID()
        let deadline = t0.addingTimeInterval(600)
        var wire = FakeWatchTransport()
        wire.send(["action": "end_session", "session_id": s.id.uuidString, "ended_at": deadline.timeIntervalSince1970,
                   StrengthCompletionKey.reason: "inactivity", StrengthCompletionKey.version: 2,
                   StrengthCompletionKey.inactivityDeadline: deadline.timeIntervalSince1970,
                   StrengthCompletionKey.completionID: cid.uuidString,
                   WatchStrengthCompletionKey.transferID: route.transferID.uuidString,
                   WatchStrengthCompletionKey.captureEpoch: route.captureEpoch.uuidString])
        clock.set(deadline)
        XCTAssertEqual(reconcile(m), .finalized)          // phone wins the race
        _ = try? ctx.save()
        for p in wire.delivered {                          // Watch packet arrives afterwards
            _ = try WatchStrengthSyncApplier.apply(userInfo: p, in: ctx, phoneActiveID: nil, acceptedWatchRoute: route)
        }
        XCTAssertEqual(s.endedAt, deadline)
        XCTAssertEqual(s.endReasonRaw, "inactivity")
        XCTAssertEqual(diag.count("finalizer"), 1, "stop/end must happen exactly once")
        XCTAssertEqual(m.finalizeStrength(sessionID: s.id, endedAt: deadline, reason: .inactivity), .alreadyEnded)
    }

    func testDuplicateAndReorderedWatchPacketsDoNotResurrectWorkout() throws {
        let (m, s, ctx) = try phone()
        clock.set(t0.addingTimeInterval(600))
        XCTAssertEqual(reconcile(m), .finalized)
        let deadline = t0.addingTimeInterval(600)
        let later = t0.addingTimeInterval(900)
        // Late legacy end, duplicate, and a stale log_set arriving out of order.
        var wire = FakeWatchTransport()
        let end: [String: Any] = ["action": "end_session", "session_id": s.id.uuidString,
                                  "ended_at": later.timeIntervalSince1970]
        wire.send(end, copies: 2)
        for p in wire.delivered.reversed() {
            _ = try WatchStrengthSyncApplier.apply(userInfo: p, in: ctx, phoneActiveID: nil)
        }
        XCTAssertEqual(s.endedAt, deadline, "terminal state dominates later/duplicate ends")
        XCTAssertEqual(s.endReasonRaw, "inactivity")
        XCTAssertFalse(m.isActive)
        XCTAssertNil(reconcile(m))
        let persisted = StrengthCompletionRecord(sessionID: s.id, completionID: nil, reason: .inactivity, endedAt: deadline)
        let route = WatchStrengthCompletionRoute(sessionID: s.id, transferID: UUID(), captureEpoch: UUID())
        let env = StrengthCompletionEnvelope(sessionID: s.id, reason: .inactivity, endedAt: deadline,
                                             inactivityDeadline: deadline, completionID: UUID(), version: 2, route: route)
        XCTAssertEqual(WatchSessionEndPolicy.decide(incoming: env, persisted: persisted, activeSessionID: nil,
                                                    acceptedWatchRoute: route), .rejectStale)
    }

    func testAutoEndedWorkoutPreservesSetsAndUsesDeadlineAsEndedAt() throws {
        let (m, s, _) = try phone()
        clock.set(t0.addingTimeInterval(7 * 3600))
        XCTAssertEqual(reconcile(m), .finalized)
        XCTAssertEqual(s.endedAt, t0.addingTimeInterval(600))
        XCTAssertNotEqual(s.endedAt, clock.now)
        XCTAssertEqual(s.orderedSets.count, 1)
        XCTAssertNil(s.deletedAt)
    }

    func testTenHourForgottenWatchWorkoutIsFinalizedOnRecovery() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let s = WorkoutSession(title: "Forgotten", date: t0)
        ctx.insert(s)
        ctx.insert(SetEntry(weight: 60, reps: 8, order: 0, completedAt: t0, session: s))
        let tracker = watchTracker()
        tracker.begin(sessionID: s.id, now: t0, timeoutMinutes: timeout, enabled: true)
        clock.set(t0.addingTimeInterval(10 * 3600))
        guard case let .finalize(rec, endedAt) = tracker.evaluate(now: clock.now, enabled: true) else {
            return XCTFail("watch watchdog: 10h-old record must finalize")
        }
        XCTAssertEqual(WatchStrengthInactivityFinalizer.finalize(sessionID: rec.sessionID, endedAt: endedAt,
                                                                 now: clock.now, context: ctx), .finalized)
        XCTAssertEqual(s.endedAt, t0.addingTimeInterval(600))
        XCTAssertLessThan(s.duration, 3600, "must not be a 10-hour workout")
    }

    // MARK: Migration, clock, property tests

    func testLegacySessionWithoutInactivityMetadataCannotBecomeTenHourWorkout() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let ctx = ModelContext(container)
        let s = WorkoutSession(title: "Legacy", date: t0)
        XCTAssertNil(s.lastMeaningfulActivityAt)
        ctx.insert(s)
        ctx.insert(SetEntry(weight: 80, reps: 5, order: 0, completedAt: t0, session: s))
        let m = ActiveWorkoutModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let alive = t0.addingTimeInterval(120)
        let hb = WorkoutHeartbeat(sessionID: s.id, lastAlive: alive, elapsed: 120, isPaused: false)
        clock.set(t0.addingTimeInterval(10 * 3600))
        m.adopt(s, heartbeat: hb, now: clock.now)
        XCTAssertEqual(s.lastMeaningfulActivityAt, alive, "recovery baselines at last proof of life")
        XCTAssertEqual(reconcile(m), .finalized)
        XCTAssertEqual(s.endedAt, alive.addingTimeInterval(600))
        XCTAssertEqual(s.orderedSets.count, 1)
    }

    func testManualAndSystemClocksHonourSleepContract() async throws {
        try await clock.sleep(until: t0.addingTimeInterval(600))
        XCTAssertEqual(clock.now, t0.addingTimeInterval(600))
        let system = SystemWorkoutInactivityClock()
        try await system.sleep(until: Date(timeIntervalSince1970: 0)) // past target returns at once
        XCTAssertGreaterThan(system.now.timeIntervalSince1970, 1_000_000_000)
    }

    func testRandomEventSequencesOnlyMeaningfulEventsExtendDeadline() throws {
        var seed: UInt64 = 0xC0FFEE
        func next() -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) }
        for _ in 0..<50 {
            var state = StrengthInactivityPolicy.State(lastMeaningfulActivityAt: t0)
            var expected = t0, now = t0
            for _ in 0..<30 {
                now = now.addingTimeInterval(TimeInterval(next() % 400)) // clock jumps incl. duplicates (0)
                if next() % 2 == 0 {
                    state.record(StrengthPassiveEvent.allCases[next() % StrengthPassiveEvent.allCases.count], at: now)
                } else {
                    state.record(StrengthActivityEvent.allCases[next() % StrengthActivityEvent.allCases.count], at: now)
                    expected = now
                }
                XCTAssertEqual(state.lastMeaningfulActivityAt, expected)
            }
            let far = now.addingTimeInterval(86_400)
            XCTAssertEqual(StrengthInactivityPolicy.evaluate(state: state, now: far, timeoutMinutes: 10, enabled: true),
                           .end(at: expected.addingTimeInterval(600)))
        }
    }
}
