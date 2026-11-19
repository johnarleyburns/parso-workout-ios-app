import Foundation
import Testing
@testable import CadenceCore

struct HealthOutboxTests {
    @Test func enqueueCoalescesAnEditToTheNewestPayload() throws {
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

        #expect(queue.items.count == 1)
        #expect(queue.items.first?.syncVersion == 11)
        #expect(queue.items.first?.payload == Data([2]))
        #expect(queue.items.first?.attemptCount == 0)
    }

    @Test func deleteBeforeFirstAttemptCancelsPendingCreate() {
        let id = UUID()
        let now = Date(timeIntervalSince1970: 100)
        let create = HealthOutboxItem(entityKind: .strengthSession, entityID: id,
                                      operation: .upsert, syncVersion: 1, enqueuedAt: now)
        let delete = HealthOutboxItem(entityKind: .strengthSession, entityID: id,
                                      operation: .delete, syncVersion: 2, enqueuedAt: now)
        var queue = HealthOutboxQueue(items: [create])
        queue.enqueue(delete)
        #expect(queue.items.isEmpty)
    }

    @Test func failedItemUsesBoundedExponentialBackoffAndBecomesDue() {
        let id = UUID()
        let now = Date(timeIntervalSince1970: 100)
        var queue = HealthOutboxQueue(items: [HealthOutboxItem(
            entityKind: .assessment, entityID: id, operation: .upsert,
            syncVersion: 1, nextAttemptAt: now, enqueuedAt: now)])

        queue.markFailed(queue.items[0].id, error: "device locked", at: now)
        #expect(queue.items[0].attemptCount == 1)
        #expect(queue.items[0].nextAttemptAt == now.addingTimeInterval(5))
        #expect(queue.due(at: now).isEmpty)
        #expect(queue.due(at: now.addingTimeInterval(5)).count == 1)

        for _ in 0..<10 {
            queue.markFailed(queue.items[0].id, error: "still locked", at: now)
        }
        #expect(queue.items[0].nextAttemptAt == now.addingTimeInterval(1_800))
    }

    @Test func fileStorePersistsAcrossInstancesAndRemovesSuccessfulItem() async throws {
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
        #expect(firstSnapshot.items.count == 1)

        let reopened = HealthOutboxStore(fileURL: url)
        let persisted = try await reopened.snapshot()
        #expect(persisted.items.first?.entityID == id)
        try await reopened.markSucceeded(persisted.items[0].id)
        let finalSnapshot = try await HealthOutboxStore(fileURL: url).snapshot()
        #expect(finalSnapshot.items.isEmpty)
    }

    @Test func jobRoundTripsAndNeverContainsPartnerSets() throws {
        let session = WorkoutSession(title: "Partner day")
        let exercise = Exercise(name: "Bench Press")
        let owner = SetEntry(weight: 80, reps: 5, exercise: exercise)
        let partner = SetEntry(weight: 60, reps: 8, exercise: exercise,
                               performedBy: Person(name: "Partner", isMe: false))
        session.sets = [owner, partner]
        let summary = try #require(HealthBackupEncoder.strengthSummary(for: session))
        let payload = summary.metadata[CladironHealthBackup.ownerSetsKey]
        #expect(payload != nil)
        #expect(payload?.contains("Partner") != true)

        let job = HealthBackupJob.strength(summary)
        let item = try HealthOutboxItem(job: job)
        #expect(try item.decodeJob() == job)
    }
}
