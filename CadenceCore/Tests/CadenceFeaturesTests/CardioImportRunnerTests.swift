#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadenceFixtures
import CadencePhoneFeatures

@MainActor
struct CardioImportRunnerTests {
    private struct SaveFailure: Error {}

    private let t0 = Date(timeIntervalSince1970: 90_000)

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func workout(_ id: UUID = UUID(), startOffset: TimeInterval = 0) -> IngestedWorkout {
        IngestedWorkout(id: id, type: .run, start: t0.addingTimeInterval(startOffset),
                        end: t0.addingTimeInterval(startOffset + 1800), importedKind: .running)
    }

    private func run(_ fake: FakeHealthProvider, _ ctx: ModelContext) async throws -> CardioImportReport {
        try await CardioImportRunner.run(provider: fake) { delta in
            try WorkoutRepository.applyCardioImport(upserts: delta.upserts,
                                                    deletedIDs: delta.deletedHealthKitUUIDs, in: ctx)
        }
    }

    @Test func lateArrivingOldWorkoutImportsAndAdvancesAnchor() async throws {
        let ctx = try makeContext(), fake = FakeHealthProvider()
        // Starts long before any prior "sync" time, but only arrives now.
        fake.pendingWorkouts = [workout(startOffset: -86_400)]
        let report = try await run(fake, ctx)
        #expect(report.inserted == 1)
        #expect(try WorkoutRepository.allCardio(ctx).count == 1)
        #expect(fake.committedAnchors.count == 1)
    }

    @Test func emptyDeltaStillAdvancesAnchor() async throws {
        let ctx = try makeContext(), fake = FakeHealthProvider()
        fake.pendingWorkouts = []
        let report = try await run(fake, ctx)
        #expect(report.inserted == 0)
        #expect(!report.changedHistory)
        #expect(fake.committedAnchors.count == 1)
    }

    @Test func fetchFailureDoesNotAdvanceAnchor() async throws {
        let ctx = try makeContext(), fake = FakeHealthProvider()
        fake.importFetchError = SaveFailure()
        do { _ = try await run(fake, ctx); Issue.record("expected throw") } catch {}
        #expect(fake.committedAnchors.isEmpty)
    }

    @Test func saveFailureKeepsAnchorAndRetryIsIdempotent() async throws {
        let ctx = try makeContext(), fake = FakeHealthProvider()
        let w = workout()
        fake.pendingWorkouts = [w]
        let first = try await fake.fetchImportedCardioDelta()
        do {
            _ = try await CardioImportRunner.run(provider: fake) { _ in throw SaveFailure() }
            Issue.record("expected throw")
        } catch is SaveFailure {}
        #expect(fake.committedAnchors.isEmpty)
        // Retry receives the same delta and anchor.
        let retry = try await fake.fetchImportedCardioDelta()
        #expect(retry == first)
        let firstRun = try await run(fake, ctx)
        let secondRun = try await run(fake, ctx)
        #expect(firstRun.inserted == 1)
        #expect(secondRun.inserted == 0)
        #expect(try WorkoutRepository.allCardio(ctx).count == 1)
    }

    @Test func cancellationDoesNotCommitAnchor() async throws {
        let ctx = try makeContext(), fake = FakeHealthProvider()
        fake.pendingWorkouts = [workout()]
        let task = Task { @MainActor in
            try await CardioImportRunner.run(provider: fake) { delta in
                withUnsafeCurrentTask { $0?.cancel() }
                return try WorkoutRepository.applyCardioImport(
                    upserts: delta.upserts, deletedIDs: [], in: ctx)
            }
        }
        do { _ = try await task.value; Issue.record("expected cancel") } catch is CancellationError {}
        #expect(fake.committedAnchors.isEmpty)
    }

    @Test func deletionRemovesOnlyImportedRows() throws {
        let ctx = try makeContext()
        let imported = workout(), other = workout(startOffset: 7200)
        _ = try WorkoutRepository.ingest([imported, other], in: ctx)
        let recorded = CardioWorkout(type: .run, start: t0.addingTimeInterval(20_000),
                                     end: t0.addingTimeInterval(21_000), healthKitWorkoutUUID: UUID())
        recorded.originValue = .cladironRecorded
        ctx.insert(recorded)
        try ctx.save()
        let report = try WorkoutRepository.applyCardioImport(
            upserts: [], deletedIDs: [imported.id, recorded.healthKitWorkoutUUID!], in: ctx)
        #expect(report.removed == 1)
        #expect(report.changedHistory)
        let live = try WorkoutRepository.allCardio(ctx)
        #expect(Set(live.compactMap(\.healthKitWorkoutUUID)) == [other.id, recorded.healthKitWorkoutUUID!])
    }
}
#endif
