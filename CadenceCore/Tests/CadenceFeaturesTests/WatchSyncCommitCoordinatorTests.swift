import XCTest
@testable import CadenceFeatures

final class WatchSyncCommitCoordinatorTests: XCTestCase {
    private func envelope(_ revision: Int, version: Int = WatchSyncHandshake.protocolVersion) -> WatchSyncHandshake.Envelope {
        .init(protocolVersion: version, revision: revision, createdAt: Date(),
              components: .init(preferences: "p\(revision)", customExercises: "c\(revision)",
                                todayPlan: "t", weekSummary: "w"))
    }

    private func committed(_ outcome: WatchSyncCommitCoordinator.Outcome) -> WatchSyncAppliedRecord? {
        if case .commit(let record) = outcome { return record }
        return nil
    }

    func testReorderedDecodeNeverAcksOlderOverNewer() throws {
        var c = WatchSyncCommitCoordinator()
        let a = envelope(1), b = envelope(2)
        XCTAssertEqual(c.accept(a, applied: nil, needsDurableExercises: true), .awaitDurable)
        XCTAssertEqual(c.accept(b, applied: nil, needsDurableExercises: true), .awaitDurable)
        XCTAssertEqual(c.durableStoreFinished(for: a, succeeded: true, applied: nil), .discard)
        let r = try XCTUnwrap(committed(c.durableStoreFinished(for: b, succeeded: true, applied: nil)))
        XCTAssertEqual(r.revision, 2)
        XCTAssertEqual(r.snapshotID, b.snapshotID)
        XCTAssertEqual(r.components, b.components)
    }

    func testStaleLateCompletionAfterNewerCommitIsDiscarded() throws {
        var c = WatchSyncCommitCoordinator()
        let a = envelope(1), b = envelope(2)
        _ = c.accept(a, applied: nil, needsDurableExercises: false)
        let applied = try XCTUnwrap(committed(c.accept(b, applied: nil, needsDurableExercises: false)))
        XCTAssertEqual(c.accept(a, applied: applied, needsDurableExercises: false), .discard)
    }

    func testDuplicateIsDiscardedAfterApplied() throws {
        var c = WatchSyncCommitCoordinator()
        let a = envelope(3)
        let r = try XCTUnwrap(committed(c.accept(a, applied: nil, needsDurableExercises: false)))
        XCTAssertEqual(c.accept(a, applied: r, needsDurableExercises: false), .discard)
    }

    func testCustomExerciseFailureDoesNotCommitAndRetrySucceeds() {
        var c = WatchSyncCommitCoordinator()
        let a = envelope(1)
        XCTAssertEqual(c.accept(a, applied: nil, needsDurableExercises: true), .awaitDurable)
        XCTAssertEqual(c.durableStoreFinished(for: a, succeeded: false, applied: nil), .failed)
        XCTAssertEqual(c.accept(a, applied: nil, needsDurableExercises: true), .awaitDurable)
        XCTAssertNotNil(committed(c.durableStoreFinished(for: a, succeeded: true, applied: nil)))
    }

    func testRelaunchMidCommitReappliesBecauseNothingWasRecorded() {
        var first = WatchSyncCommitCoordinator()
        let a = envelope(5)
        XCTAssertEqual(first.accept(a, applied: nil, needsDurableExercises: true), .awaitDurable)
        var relaunched = WatchSyncCommitCoordinator(appliedRevision: 0)
        XCTAssertEqual(relaunched.accept(a, applied: nil, needsDurableExercises: true), .awaitDurable)
    }

    func testProtocolMismatchKeepsPriorState() {
        var c = WatchSyncCommitCoordinator()
        XCTAssertEqual(c.accept(envelope(9, version: 99), applied: nil, needsDurableExercises: false), .discard)
        XCTAssertEqual(c.highestAccepted, 0)
        XCTAssertNil(c.awaiting)
    }
}
