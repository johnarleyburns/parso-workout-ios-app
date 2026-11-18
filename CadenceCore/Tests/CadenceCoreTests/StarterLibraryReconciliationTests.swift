import XCTest
import SwiftData
@testable import CadenceCore

/// The launch-time catalog reconciliation is gated so it no longer runs on
/// every launch and foreground. These pin when it must still run.
@MainActor
final class StarterLibraryReconciliationTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "StarterLibraryReconciliationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    func testFirstRunReconcilesAndSeedsTheCatalog() throws {
        let ctx = try makeContext()
        XCTAssertTrue(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults))
        XCTAssertEqual(try WorkoutRepository.allExercises(ctx).count, ExerciseLibrary.starter.count)
    }

    func testUnchangedStoreAndRevisionSkips() throws {
        let ctx = try makeContext()
        try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults)
        XCTAssertFalse(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults))
        XCTAssertFalse(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults))
    }

    func testNewRevisionReconcilesOnce() throws {
        let ctx = try makeContext()
        try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults)
        XCTAssertTrue(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r2", defaults: defaults))
        XCTAssertFalse(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r2", defaults: defaults))
    }

    func testAddedExerciseRowReconciles() throws {
        let ctx = try makeContext()
        try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults)
        ctx.insert(Exercise(name: "Synced Custom Lift", isCustom: true))
        try ctx.save()
        XCTAssertTrue(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults))
    }

    func testDeletedBuiltInIsRestoredOnTheNextRun() throws {
        let ctx = try makeContext()
        try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults)
        let victim = try XCTUnwrap(try WorkoutRepository.allExercises(ctx).first { !$0.isCustom })
        ctx.delete(victim)
        try ctx.save()
        XCTAssertTrue(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults))
        XCTAssertEqual(try WorkoutRepository.allExercises(ctx).count, ExerciseLibrary.starter.count)
    }

    func testEditedExerciseRowReconciles() throws {
        let ctx = try makeContext()
        try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults)
        let edited = try XCTUnwrap(try WorkoutRepository.allExercises(ctx).first)
        edited.updatedAt = Date().addingTimeInterval(3_600)
        try ctx.save()
        XCTAssertTrue(try StarterLibraryReconciliation.reconcileIfStale(ctx, revision: "r1", defaults: defaults))
    }

    func testStoreSignatureTracksCountAndNewestEdit() throws {
        let ctx = try makeContext()
        XCTAssertEqual(try StarterLibraryReconciliation.storeSignature(ctx), "0|0.0")
        let first = Exercise(name: "A", updatedAt: Date(timeIntervalSince1970: 10))
        ctx.insert(first)
        ctx.insert(Exercise(name: "B", updatedAt: Date(timeIntervalSince1970: 20)))
        try ctx.save()
        XCTAssertEqual(try StarterLibraryReconciliation.storeSignature(ctx), "2|20.0")
        first.updatedAt = Date(timeIntervalSince1970: 30)
        try ctx.save()
        XCTAssertEqual(try StarterLibraryReconciliation.storeSignature(ctx), "2|30.0")
    }

    func testRevisionIncludesSeedVersion() {
        XCTAssertTrue(StarterLibraryReconciliation.revision().hasPrefix("seed\(ExerciseLibrary.seedVersion)-build"))
    }
}

/// The bounded history fetches that replaced whole-log `@Query`s on the
/// workout screen.
@MainActor
final class BoundedSessionFetchTests: XCTestCase {
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

    func testRecentSessionsAreNewestFirstLimitedAndSkipDeleted() throws {
        let ctx = try makeContext()
        try insertSessions(ctx, days: [1, 2, 3, 4, 5], deleted: [4])
        let recent = try WorkoutRepository.recentSessions(ctx, limit: 3)
        XCTAssertEqual(recent.map(\.title), ["Day 5", "Day 3", "Day 2"])
    }

    func testRecentSessionsWithNonPositiveLimitIsEmpty() throws {
        let ctx = try makeContext()
        try insertSessions(ctx, days: [1, 2])
        XCTAssertTrue(try WorkoutRepository.recentSessions(ctx, limit: 0).isEmpty)
    }

    func testSessionsSinceIncludesTheStartAndSkipsDeleted() throws {
        let ctx = try makeContext()
        try insertSessions(ctx, days: [1, 2, 3, 4], deleted: [4])
        let since = try WorkoutRepository.sessions(since: Date(timeIntervalSince1970: 2 * 86_400), in: ctx)
        XCTAssertEqual(since.map(\.title), ["Day 3", "Day 2"])
    }
}
