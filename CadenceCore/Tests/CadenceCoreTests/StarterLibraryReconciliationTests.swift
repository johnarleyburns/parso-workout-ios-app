#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

/// The launch-time catalog reconciliation is gated so it no longer runs on
/// every launch and foreground. These pin when it must still run.
@MainActor
@Suite final class StarterLibraryReconciliationTests {
    private let defaults = InMemoryDefaultsStore()

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    @Test func firstRunReconcilesAndSeedsTheCatalog() throws {
        let ctx = try makeContext()
        #expect(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults))
        #expect(try WorkoutRepository.allExercises(ctx).count == ExerciseLibrary.starter.count)
    }

    @Test func unchangedStoreAndRevisionSkips() throws {
        let ctx = try makeContext()
        try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults)
        #expect(!(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults)))
        #expect(!(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults)))
    }

    @Test func newRevisionReconcilesOnce() throws {
        let ctx = try makeContext()
        try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults)
        #expect(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r2", defaults: defaults))
        #expect(!(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r2", defaults: defaults)))
    }

    @Test func addedExerciseRowReconciles() throws {
        let ctx = try makeContext()
        try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults)
        ctx.insert(Exercise(name: "Synced Custom Lift", isCustom: true))
        try ctx.save()
        #expect(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults))
    }

    @Test func deletedBuiltInIsRestoredOnTheNextRun() throws {
        let ctx = try makeContext()
        try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults)
        let victim = try #require(try WorkoutRepository.allExercises(ctx).first { !$0.isCustom })
        ctx.delete(victim)
        try ctx.save()
        #expect(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults))
        #expect(try WorkoutRepository.allExercises(ctx).count == ExerciseLibrary.starter.count)
    }

    @Test func editedExerciseRowReconciles() throws {
        let ctx = try makeContext()
        try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults)
        let edited = try #require(try WorkoutRepository.allExercises(ctx).first)
        edited.updatedAt = Date().addingTimeInterval(3_600)
        try ctx.save()
        #expect(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults))
    }

    @Test func storeSignatureTracksCountAndNewestEdit() throws {
        let ctx = try makeContext()
        #expect(try StarterLibraryReconciliation.storeSignature(ctx) == "0|0.0")
        let first = Exercise(name: "A", updatedAt: Date(timeIntervalSince1970: 10))
        ctx.insert(first)
        ctx.insert(Exercise(name: "B", updatedAt: Date(timeIntervalSince1970: 20)))
        try ctx.save()
        #expect(try StarterLibraryReconciliation.storeSignature(ctx) == "2|20.0")
        first.updatedAt = Date(timeIntervalSince1970: 30)
        try ctx.save()
        #expect(try StarterLibraryReconciliation.storeSignature(ctx) == "2|30.0")
    }

    @Test func revisionIncludesSeedVersion() {
        #expect(StarterLibraryReconciliation.revision().hasPrefix("seed\(ExerciseLibrary.seedVersion)-build"))
    }
}

/// The bounded history fetches that replaced whole-log `@Query`s on the
/// workout screen.
@MainActor
struct BoundedSessionFetchTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func insertSessions(_ ctx: ModelContext, days: [Int], deleted: Set<Int> = []) throws {
        for day in days {
            let session = WorkoutSession(title: "Day \(day)", date: Date(timeIntervalSince1970: Double(day) * 86_400))
            if deleted.contains(day) { session.deletedAt = Date() }
            ctx.insert(session)
        }
        try ctx.save()
    }

    @Test func recentSessionsAreNewestFirstLimitedAndSkipDeleted() throws {
        let ctx = try makeContext()
        try insertSessions(ctx, days: [1, 2, 3, 4, 5], deleted: [4])
        let recent = try WorkoutRepository.recentSessions(ctx, limit: 3)
        #expect(recent.map(\.title) == ["Day 5", "Day 3", "Day 2"])
    }

    @Test func recentSessionsWithNonPositiveLimitIsEmpty() throws {
        let ctx = try makeContext()
        try insertSessions(ctx, days: [1, 2])
        #expect(try WorkoutRepository.recentSessions(ctx, limit: 0).isEmpty)
    }

    @Test func sessionsSinceIncludesTheStartAndSkipsDeleted() throws {
        let ctx = try makeContext()
        try insertSessions(ctx, days: [1, 2, 3, 4], deleted: [4])
        let since = try WorkoutRepository.sessions(since: Date(timeIntervalSince1970: 2 * 86_400), in: ctx)
        #expect(since.map(\.title) == ["Day 3", "Day 2"])
    }
}
#endif
