import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct WatchSyncCommitCoordinatorTests {
    private func envelope(_ revision: Int, version: Int = WatchSyncHandshake.protocolVersion) -> WatchSyncHandshake.Envelope {
        .init(protocolVersion: version, revision: revision, createdAt: Date(),
              components: .init(preferences: "p\(revision)", customExercises: "c\(revision)",
                                todayPlan: "t", weekSummary: "w"))
    }

    private func committed(_ outcome: WatchSyncCommitCoordinator.Outcome) -> WatchSyncAppliedRecord? {
        if case .commit(let record) = outcome { return record }
        return nil
    }

    @Test func reorderedDecodeNeverAcksOlderOverNewer() throws {
        var c = WatchSyncCommitCoordinator()
        let a = envelope(1), b = envelope(2)
        let acceptA = c.accept(a, applied: nil, needsDurableExercises: true)
        #expect(acceptA == .awaitDurable)
        let acceptB = c.accept(b, applied: nil, needsDurableExercises: true)
        #expect(acceptB == .awaitDurable)
        let finishedA = c.durableStoreFinished(for: a, succeeded: true, applied: nil)
        #expect(finishedA == .discard)
        let finishedB = c.durableStoreFinished(for: b, succeeded: true, applied: nil)
        let r = try #require(committed(finishedB))
        #expect(r.revision == 2)
        #expect(r.snapshotID == b.snapshotID)
        #expect(r.components == b.components)
    }

    @Test func staleLateCompletionAfterNewerCommitIsDiscarded() throws {
        var c = WatchSyncCommitCoordinator()
        let a = envelope(1), b = envelope(2)
        _ = c.accept(a, applied: nil, needsDurableExercises: false)
        let acceptB = c.accept(b, applied: nil, needsDurableExercises: false)
        let applied = try #require(committed(acceptB))
        let acceptAAgain = c.accept(a, applied: applied, needsDurableExercises: false)
        #expect(acceptAAgain == .discard)
    }

    @Test func duplicateIsDiscardedAfterApplied() throws {
        var c = WatchSyncCommitCoordinator()
        let a = envelope(3)
        let acceptA = c.accept(a, applied: nil, needsDurableExercises: false)
        let r = try #require(committed(acceptA))
        let acceptAAgain = c.accept(a, applied: r, needsDurableExercises: false)
        #expect(acceptAAgain == .discard)
    }

    @Test func customExerciseFailureDoesNotCommitAndRetrySucceeds() {
        var c = WatchSyncCommitCoordinator()
        let a = envelope(1)
        let accept1 = c.accept(a, applied: nil, needsDurableExercises: true)
        #expect(accept1 == .awaitDurable)
        let finished1 = c.durableStoreFinished(for: a, succeeded: false, applied: nil)
        #expect(finished1 == .failed)
        let accept2 = c.accept(a, applied: nil, needsDurableExercises: true)
        #expect(accept2 == .awaitDurable)
        let finished2 = c.durableStoreFinished(for: a, succeeded: true, applied: nil)
        #expect(committed(finished2) != nil)
    }

    @Test func relaunchMidCommitReappliesBecauseNothingWasRecorded() {
        var first = WatchSyncCommitCoordinator()
        let a = envelope(5)
        let acceptFirst = first.accept(a, applied: nil, needsDurableExercises: true)
        #expect(acceptFirst == .awaitDurable)
        var relaunched = WatchSyncCommitCoordinator(appliedRevision: 0)
        let acceptRelaunched = relaunched.accept(a, applied: nil, needsDurableExercises: true)
        #expect(acceptRelaunched == .awaitDurable)
    }

    @Test func protocolMismatchKeepsPriorState() {
        var c = WatchSyncCommitCoordinator()
        let accept = c.accept(envelope(9, version: 99), applied: nil, needsDurableExercises: false)
        #expect(accept == .discard)
        #expect(c.highestAccepted == 0)
        #expect(c.awaiting == nil)
    }
}
