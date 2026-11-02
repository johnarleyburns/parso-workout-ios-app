import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

@MainActor
final class WatchStrengthInactivityTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let sessionID = UUID()

    private func makeTracker() -> WatchStrengthInactivityTracker {
        WatchStrengthInactivityTracker(store: .init(suiteName: "watch.inactivity.tests.\(UUID().uuidString)"))
    }

    func testRecordRoundTripsThroughDurableStoreAndUsesPolicyDeadline() throws {
        let tracker = makeTracker()
        let record = try XCTUnwrap(tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true))
        XCTAssertEqual(tracker.record, record)
        XCTAssertEqual(record.deadline, t0.addingTimeInterval(600))
        // A new tracker over the same store (process relaunch) sees the same deadline.
        XCTAssertEqual(WatchStrengthInactivityTracker(store: tracker.store).record?.deadline, record.deadline)
    }

    func testExactTenMinuteBoundary() {
        let tracker = makeTracker()
        tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true)
        XCTAssertEqual(tracker.evaluate(now: t0.addingTimeInterval(599), enabled: true),
                       .waiting(until: t0.addingTimeInterval(600)))
        guard case let .finalize(_, endedAt) = tracker.evaluate(now: t0.addingTimeInterval(600), enabled: true) else {
            return XCTFail("deadline reached must finalize")
        }
        XCTAssertEqual(endedAt, t0.addingTimeInterval(600))
    }

    func testSetRearmsDeadlineAndLateGestureCannotResurrect() throws {
        let tracker = makeTracker()
        tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true)
        let rearmed = try XCTUnwrap(tracker.recordActivity(.setMutation, now: t0.addingTimeInterval(599)))
        XCTAssertEqual(rearmed.deadline, t0.addingTimeInterval(599 + 600))
        XCTAssertNil(tracker.recordActivity(.setMutation, now: t0.addingTimeInterval(599 + 600)),
                     "an overdue workout is reconciled, not extended")
    }

    func testRecoveryUsesStoredDeadlineNotRecoveryTime() {
        let tracker = makeTracker()
        tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true)
        let late = t0.addingTimeInterval(3 * 3600)
        guard case let .finalize(_, endedAt) = tracker.evaluate(now: late, enabled: true) else {
            return XCTFail("overdue record must finalize")
        }
        XCTAssertEqual(endedAt, t0.addingTimeInterval(600))
        // Evaluating (recovery, HR, appearance) never moves it.
        XCTAssertEqual(tracker.record?.lastMeaningfulActivityAt, t0)
    }

    func testDisabledSettingCreatesNoRecordAndNeverEnds() {
        let tracker = makeTracker()
        XCTAssertNil(tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: false))
        XCTAssertEqual(tracker.evaluate(now: t0.addingTimeInterval(9999), enabled: false), .noRecord)
        tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true)
        XCTAssertEqual(tracker.evaluate(now: t0.addingTimeInterval(9999), enabled: false), .disabled)
    }

    func testBeginKeepsExistingRecordForSameSession() throws {
        let tracker = makeTracker()
        tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true)
        let again = try XCTUnwrap(tracker.begin(sessionID: sessionID, now: t0.addingTimeInterval(300),
                                                timeoutMinutes: 10, enabled: true))
        XCTAssertEqual(again.lastMeaningfulActivityAt, t0, "re-creating a view must not reset the deadline")
    }

    func testStaleGenerationDoesNotClearNewerRecord() throws {
        let tracker = makeTracker()
        let old = try XCTUnwrap(tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true))
        tracker.clear()
        let newer = try XCTUnwrap(tracker.begin(sessionID: UUID(), now: t0, timeoutMinutes: 10, enabled: true))
        tracker.clear(matching: old.sessionGeneration)
        XCTAssertEqual(tracker.record, newer)
        tracker.clear(matching: newer.sessionGeneration)
        XCTAssertNil(tracker.record)
    }

    // MARK: - Finalizer / flow

    func testFlowStartLogSetThenAutoFinishAtDeadlinePreservesSetsAndIsIdempotent() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
        let model = WatchStrengthFlowModel(context: context, unit: .kilograms, cooldownDefault: 5, restDefault: 30)
        model.start(title: "Push", plannedExerciseNames: ["Bench Press"], createSession: true)
        let exercise = try XCTUnwrap(model.exerciseList.first?.exercise)
        model.startLogSet(for: exercise)
        _ = model.logSet()
        let session = try XCTUnwrap(model.session)
        let tracker = makeTracker()
        tracker.begin(sessionID: session.id, now: t0, timeoutMinutes: 10, enabled: true)

        guard case let .finalize(record, endedAt) = tracker.evaluate(now: t0.addingTimeInterval(600), enabled: true) else {
            return XCTFail("expected finalize")
        }
        let now = t0.addingTimeInterval(700)
        XCTAssertEqual(WatchStrengthInactivityFinalizer.finalize(sessionID: record.sessionID, endedAt: endedAt,
                                                                 now: now, context: context), .finalized)
        XCTAssertEqual(session.endedAt, t0.addingTimeInterval(600))
        XCTAssertEqual(session.endReasonRaw, "inactivity")
        XCTAssertEqual(session.orderedSets.count, 1)

        // End payload carries the exact end time.
        let relaunched = WatchStrengthFlowModel(context: context)
        relaunched.start(resuming: session)
        let payload = try XCTUnwrap(relaunched.endSessionPayload())
        XCTAssertEqual(payload["ended_at"] as? Double, endedAt.timeIntervalSince1970)

        tracker.clear(matching: record.sessionGeneration)
        XCTAssertNil(tracker.record)
        XCTAssertEqual(WatchStrengthInactivityFinalizer.finalize(sessionID: record.sessionID, endedAt: endedAt,
                                                                 now: now, context: context), .alreadyEnded)
        XCTAssertEqual(session.endedAt, t0.addingTimeInterval(600), "repeat reconciliation is a no-op")
    }

    func testNoSetSessionIsDiscardedLikeExplicitFinish() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        let model = WatchStrengthFlowModel(context: context)
        model.start(title: "Empty", createSession: true)
        let id = try XCTUnwrap(model.session?.id)
        XCTAssertEqual(WatchStrengthInactivityFinalizer.finalize(sessionID: id, endedAt: t0, now: t0, context: context),
                       .discardedEmpty)
        XCTAssertEqual(WatchStrengthInactivityFinalizer.finalize(sessionID: id, endedAt: t0, now: t0, context: context),
                       .missingSession)
    }

    func testNoticeRoundTripAndMessage() {
        let tracker = makeTracker()
        let notice = WatchStrengthInactivityNotice(sessionID: sessionID, endedAt: t0, timeoutMinutes: 10, keptSets: true)
        tracker.store.saveNotice(notice)
        XCTAssertEqual(tracker.store.loadNotice(), notice)
        XCTAssertEqual(notice.message, "Workout ended after 10 minutes inactive")
        tracker.store.saveNotice(nil)
        XCTAssertNil(tracker.store.loadNotice())
    }

    // MARK: - Orphan safety net

    func testOrphanPolicyYieldsToLiveRecordButStaysFallbackWithoutOne() {
        let started = t0
        let now = t0.addingTimeInterval(5 * 3600)
        func input(deadline: Date?) -> WatchSessionOwnership.Input {
            .init(isRunning: true, startedAt: started, workoutType: "strength", workoutScreenVisible: false,
                  ownedByPhone: false, hasResumableStrength: true, inactivityDeadline: deadline)
        }
        XCTAssertEqual(WatchSessionOwnership.verdict(input(deadline: now.addingTimeInterval(60)), now: now), .owned)
        XCTAssertEqual(WatchSessionOwnership.verdict(input(deadline: nil), now: now), .endNow(startedAt: started),
                       "pre-migration session with no record keeps the 4-hour fallback")
        XCTAssertEqual(WatchSessionOwnership.verdict(input(deadline: now.addingTimeInterval(-60)), now: now),
                       .endNow(startedAt: started))
        XCTAssertEqual(WatchSessionOwnership.backgroundVerdict(
            startedAt: started, ownedByPhone: false, inactivityDeadline: now.addingTimeInterval(1), now: now), .owned)
    }
}
