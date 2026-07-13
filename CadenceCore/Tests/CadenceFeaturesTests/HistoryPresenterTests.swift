import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

@MainActor
final class HistoryPresenterTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    func testMergesAndSortsNewestFirst() throws {
        let ctx = try makeContext()
        let now = Date()
        let s1 = WorkoutSession(title: "Old", date: now.addingTimeInterval(-3 * 86_400))
        let s2 = WorkoutSession(title: "New", date: now.addingTimeInterval(-1 * 86_400))
        ctx.insert(s1); ctx.insert(s2)
        let c = CardioWorkout(type: .run, start: now.addingTimeInterval(-2 * 86_400),
                              end: now.addingTimeInterval(-2 * 86_400 + 1800), source: .iphone)
        ctx.insert(c)
        try ctx.save()

        let entries = HistoryPresenter.entries(sessions: [s1, s2], cardio: [c])
        XCTAssertEqual(entries.count, 3)
        // Newest-first: s2 (1d), c (2d), s1 (3d)
        XCTAssertGreaterThanOrEqual(entries[0].date, entries[1].date)
        XCTAssertGreaterThanOrEqual(entries[1].date, entries[2].date)
        XCTAssertEqual(entries.first?.date, s2.date)
    }

    func testSoftDeletedExcludedByDefault() throws {
        let ctx = try makeContext()
        let live = WorkoutSession(title: "Live", date: Date())
        let dead = WorkoutSession(title: "Dead", date: Date())
        dead.deletedAt = Date()
        ctx.insert(live); ctx.insert(dead)
        try ctx.save()

        let entries = HistoryPresenter.entries(sessions: [live, dead], cardio: [])
        XCTAssertEqual(entries.count, 1)
    }

    func testShowDeletedReturnsOnlyDeleted() throws {
        let ctx = try makeContext()
        let live = WorkoutSession(title: "Live", date: Date())
        let dead = WorkoutSession(title: "Dead", date: Date())
        dead.deletedAt = Date()
        ctx.insert(live); ctx.insert(dead)
        let deadCardio = CardioWorkout(type: .walk, start: Date(), end: Date().addingTimeInterval(600), source: .iphone)
        deadCardio.deletedAt = Date()
        ctx.insert(deadCardio)
        try ctx.save()

        let entries = HistoryPresenter.entries(sessions: [live, dead], cardio: [deadCardio], showDeleted: true)
        XCTAssertEqual(entries.count, 2)
    }
}
