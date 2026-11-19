#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

@MainActor
struct WatchStrengthInactivityTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let sessionID = UUID()

    private func makeTracker() -> WatchStrengthInactivityTracker {
        WatchStrengthInactivityTracker(store: .init(suiteName: "watch.inactivity.tests.\(UUID().uuidString)"))
    }

    @Test func recordRoundTripsThroughDurableStoreAndUsesPolicyDeadline() throws {
        let tracker = makeTracker()
        let record = try #require(tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true))
        #expect(tracker.record == record)
        #expect(record.deadline == t0.addingTimeInterval(600))
        // A new tracker over the same store (process relaunch) sees the same deadline.
        #expect(WatchStrengthInactivityTracker(store: tracker.store).record?.deadline == record.deadline)
    }

    @Test func exactTenMinuteBoundary() {
        let tracker = makeTracker()
        tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true)
        #expect(tracker.evaluate(now: t0.addingTimeInterval(599), enabled: true) ==
                       .waiting(until: t0.addingTimeInterval(600)))
        guard case let .finalize(_, endedAt) = tracker.evaluate(now: t0.addingTimeInterval(600), enabled: true) else {
            Issue.record("deadline reached must finalize")
            return
        }
        #expect(endedAt == t0.addingTimeInterval(600))
    }

    @Test func setRearmsDeadlineAndLateGestureCannotResurrect() throws {
        let tracker = makeTracker()
        tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true)
        let rearmed = try #require(tracker.recordActivity(.setMutation, now: t0.addingTimeInterval(599)))
        #expect(rearmed.deadline == t0.addingTimeInterval(599 + 600))
        #expect(tracker.recordActivity(.setMutation, now: t0.addingTimeInterval(599 + 600)) == nil,
                     "an overdue workout is reconciled, not extended")
    }

    @Test func recoveryUsesStoredDeadlineNotRecoveryTime() {
        let tracker = makeTracker()
        tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true)
        let late = t0.addingTimeInterval(3 * 3600)
        guard case let .finalize(_, endedAt) = tracker.evaluate(now: late, enabled: true) else {
            Issue.record("overdue record must finalize")
            return
        }
        #expect(endedAt == t0.addingTimeInterval(600))
        // Evaluating (recovery, HR, appearance) never moves it.
        #expect(tracker.record?.lastMeaningfulActivityAt == t0)
    }

    @Test func disabledSettingCreatesNoRecordAndNeverEnds() {
        let tracker = makeTracker()
        #expect(tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: false) == nil)
        #expect(tracker.evaluate(now: t0.addingTimeInterval(9999), enabled: false) == .noRecord)
        tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true)
        #expect(tracker.evaluate(now: t0.addingTimeInterval(9999), enabled: false) == .disabled)
    }

    @Test func beginKeepsExistingRecordForSameSession() throws {
        let tracker = makeTracker()
        tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true)
        let again = try #require(tracker.begin(sessionID: sessionID, now: t0.addingTimeInterval(300),
                                                timeoutMinutes: 10, enabled: true))
        #expect(again.lastMeaningfulActivityAt == t0, "re-creating a view must not reset the deadline")
    }

    @Test func staleGenerationDoesNotClearNewerRecord() throws {
        let tracker = makeTracker()
        let old = try #require(tracker.begin(sessionID: sessionID, now: t0, timeoutMinutes: 10, enabled: true))
        tracker.clear()
        let newer = try #require(tracker.begin(sessionID: UUID(), now: t0, timeoutMinutes: 10, enabled: true))
        tracker.clear(matching: old.sessionGeneration)
        #expect(tracker.record == newer)
        tracker.clear(matching: newer.sessionGeneration)
        #expect(tracker.record == nil)
    }

    // MARK: - Finalizer / flow

    @Test func flowStartLogSetThenAutoFinishAtDeadlinePreservesSetsAndIsIdempotent() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
        let model = WatchStrengthFlowModel(context: context, unit: .kilograms, cooldownDefault: 5, restDefault: 30)
        model.start(title: "Push", plannedExerciseNames: ["Bench Press"], createSession: true)
        let exercise = try #require(model.exerciseList.first?.exercise)
        model.startLogSet(for: exercise)
        _ = model.logSet()
        let session = try #require(model.session)
        let tracker = makeTracker()
        tracker.begin(sessionID: session.id, now: t0, timeoutMinutes: 10, enabled: true)

        guard case let .finalize(record, endedAt) = tracker.evaluate(now: t0.addingTimeInterval(600), enabled: true) else {
            Issue.record("expected finalize")
            return
        }
        let now = t0.addingTimeInterval(700)
        #expect(WatchStrengthInactivityFinalizer.finalize(sessionID: record.sessionID, endedAt: endedAt,
                                                                 now: now, context: context) == .finalized)
        #expect(session.endedAt == t0.addingTimeInterval(600))
        #expect(session.endReasonRaw == "inactivity")
        #expect(session.orderedSets.count == 1)

        // End payload carries the exact end time.
        let relaunched = WatchStrengthFlowModel(context: context)
        relaunched.start(resuming: session)
        let payload = try #require(relaunched.endSessionPayload())
        #expect(payload["ended_at"] as? Double == endedAt.timeIntervalSince1970)

        tracker.clear(matching: record.sessionGeneration)
        #expect(tracker.record == nil)
        #expect(WatchStrengthInactivityFinalizer.finalize(sessionID: record.sessionID, endedAt: endedAt,
                                                                 now: now, context: context) == .alreadyEnded)
        #expect(session.endedAt == t0.addingTimeInterval(600), "repeat reconciliation is a no-op")
    }

    @Test func noSetSessionIsDiscardedLikeExplicitFinish() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        let model = WatchStrengthFlowModel(context: context)
        model.start(title: "Empty", createSession: true)
        let id = try #require(model.session?.id)
        #expect(WatchStrengthInactivityFinalizer.finalize(sessionID: id, endedAt: t0, now: t0, context: context) ==
                       .discardedEmpty)
        #expect(WatchStrengthInactivityFinalizer.finalize(sessionID: id, endedAt: t0, now: t0, context: context) ==
                       .missingSession)
    }

    @Test func noticeRoundTripAndMessage() {
        let tracker = makeTracker()
        let notice = WatchStrengthInactivityNotice(sessionID: sessionID, endedAt: t0, timeoutMinutes: 10, keptSets: true)
        tracker.store.saveNotice(notice)
        #expect(tracker.store.loadNotice() == notice)
        #expect(notice.message == "Workout ended after 10 minutes inactive")
        tracker.store.saveNotice(nil)
        #expect(tracker.store.loadNotice() == nil)
    }

    // MARK: - Orphan safety net

    @Test func orphanPolicyYieldsToLiveRecordButStaysFallbackWithoutOne() {
        let started = t0
        let now = t0.addingTimeInterval(5 * 3600)
        func input(deadline: Date?) -> WatchSessionOwnership.Input {
            .init(isRunning: true, startedAt: started, workoutType: "strength", workoutScreenVisible: false,
                  ownedByPhone: false, hasResumableStrength: true, inactivityDeadline: deadline)
        }
        #expect(WatchSessionOwnership.verdict(input(deadline: now.addingTimeInterval(60)), now: now) == .owned)
        #expect(WatchSessionOwnership.verdict(input(deadline: nil), now: now) == .endNow(startedAt: started),
                       "pre-migration session with no record keeps the 4-hour fallback")
        #expect(WatchSessionOwnership.verdict(input(deadline: now.addingTimeInterval(-60)), now: now) ==
                       .endNow(startedAt: started))
        #expect(WatchSessionOwnership.backgroundVerdict(
            startedAt: started, ownedByPhone: false, inactivityDeadline: now.addingTimeInterval(1), now: now) == .owned)
    }
}
#endif
