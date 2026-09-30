import XCTest
@testable import CadenceCore

final class HealthOutboxTests: XCTestCase {
    func testEnqueueCoalescesAnEditToTheNewestPayload() throws {
        let id = UUID()
        let first = HealthOutboxItem(entityKind: .cardioWorkout, entityID: id,
                                     operation: .upsert, syncVersion: 10,
                                     payload: Data([1]), nextAttemptAt: .distantPast,
                                     enqueuedAt: Date(timeIntervalSince1970: 10))
        let second = HealthOutboxItem(entityKind: .cardioWorkout, entityID: id,
                                      operation: .upsert, syncVersion: 11,
                                      payload: Data([2]), enqueuedAt: Date(timeIntervalSince1970: 11))
        var queue = HealthOutboxQueue(items: [first])
        queue.enqueue(second)

        XCTAssertEqual(queue.items.count, 1)
        XCTAssertEqual(queue.items.first?.syncVersion, 11)
        XCTAssertEqual(queue.items.first?.payload, Data([2]))
        XCTAssertEqual(queue.items.first?.attemptCount, 0)
    }

    func testDeleteBeforeFirstAttemptCancelsPendingCreate() {
        let id = UUID()
        let now = Date(timeIntervalSince1970: 100)
        let create = HealthOutboxItem(entityKind: .strengthSession, entityID: id,
                                      operation: .upsert, syncVersion: 1, enqueuedAt: now)
        let delete = HealthOutboxItem(entityKind: .strengthSession, entityID: id,
                                      operation: .delete, syncVersion: 2, enqueuedAt: now)
        var queue = HealthOutboxQueue(items: [create])
        queue.enqueue(delete)
        XCTAssertTrue(queue.items.isEmpty)
    }

    func testFailedItemUsesBoundedExponentialBackoffAndBecomesDue() {
        let id = UUID()
        let now = Date(timeIntervalSince1970: 100)
        var queue = HealthOutboxQueue(items: [HealthOutboxItem(
            entityKind: .assessment, entityID: id, operation: .upsert,
            syncVersion: 1, nextAttemptAt: now, enqueuedAt: now)])

        queue.markFailed(queue.items[0].id, error: "device locked", at: now)
        XCTAssertEqual(queue.items[0].attemptCount, 1)
        XCTAssertEqual(queue.items[0].nextAttemptAt, now.addingTimeInterval(5))
        XCTAssertTrue(queue.due(at: now).isEmpty)
        XCTAssertEqual(queue.due(at: now.addingTimeInterval(5)).count, 1)

        for _ in 0..<10 {
            queue.markFailed(queue.items[0].id, error: "still locked", at: now)
        }
        XCTAssertEqual(queue.items[0].nextAttemptAt, now.addingTimeInterval(1_800))
    }

    func testFileStorePersistsAcrossInstancesAndRemovesSuccessfulItem() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthOutbox-(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("outbox.json")
        let id = UUID()
        let item = HealthOutboxItem(entityKind: .cardioWorkout, entityID: id,
                                    operation: .upsert, syncVersion: 4,
                                    payload: Data([4]))

        let first = HealthOutboxStore(fileURL: url)
        try await first.enqueue(item)
        let firstSnapshot = try await first.snapshot()
        XCTAssertEqual(firstSnapshot.items.count, 1)

        let reopened = HealthOutboxStore(fileURL: url)
        let persisted = try await reopened.snapshot()
        XCTAssertEqual(persisted.items.first?.entityID, id)
        try await reopened.markSucceeded(persisted.items[0].id)
        let finalSnapshot = try await HealthOutboxStore(fileURL: url).snapshot()
        XCTAssertTrue(finalSnapshot.items.isEmpty)
    }

    func testJobRoundTripsAndNeverContainsPartnerSets() throws {
        let session = WorkoutSession(title: "Partner day")
        let exercise = Exercise(name: "Bench Press")
        let owner = SetEntry(weight: 80, reps: 5, exercise: exercise)
        let partner = SetEntry(weight: 60, reps: 8, exercise: exercise,
                               performedBy: Person(name: "Partner", isMe: false))
        session.sets = [owner, partner]
        let summary = try XCTUnwrap(HealthBackupEncoder.strengthSummary(for: session))
        let payload = summary.metadata[CladironHealthBackup.ownerSetsKey]
        XCTAssertNotNil(payload)
        XCTAssertFalse(payload?.contains("Partner") == true)

        let job = HealthBackupJob.strength(summary)
        let item = try HealthOutboxItem(job: job)
        XCTAssertEqual(try item.decodeJob(), job)
    }
}
