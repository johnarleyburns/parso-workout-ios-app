import XCTest
import SwiftData
@testable import CadenceCore

/// Regression test for the schema-3 data-loss incident: a completed workout
/// must survive the same local-store reopen used by an app update.
@MainActor
final class CompletedHistoryPersistenceSafetyTests: XCTestCase {
    func testReopeningPersistentStorePreservesCompletedWorkout() throws {
        let directory = try makeTemporaryStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("history.store")
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        try saveCompletedWorkout(id: id, start: start, at: storeURL)

        let reopened = try CadenceStore.makeModelContainer(inMemory: false,
                                                            cloudKitEnabled: false,
                                                            storeURL: storeURL)
        let context = ModelContext(reopened)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let session = try XCTUnwrap(sessions.first(where: { $0.id == id }))
        XCTAssertEqual(session.title, "Persistence Regression")
        XCTAssertEqual(session.date, start)
        XCTAssertEqual(session.endedAt, start.addingTimeInterval(1_800))
        XCTAssertEqual(session.orderedSets.count, 1)
        XCTAssertEqual(session.orderedSets.first?.reps, 8)
    }

    private func saveCompletedWorkout(id: UUID, start: Date, at storeURL: URL) throws {
        let container = try CadenceStore.makeModelContainer(inMemory: false,
                                                            cloudKitEnabled: false,
                                                            storeURL: storeURL)
        let context = ModelContext(container)
        let session = WorkoutSession(id: id, title: "Persistence Regression", date: start,
                                     endedAt: start.addingTimeInterval(1_800))
        let exercise = Exercise(name: "Persistence Test Exercise")
        let set = SetEntry(weight: 50, reps: 8, order: 0,
                           completedAt: start.addingTimeInterval(900),
                           session: session, exercise: exercise)
        context.insert(exercise)
        context.insert(session)
        context.insert(set)
        try context.save()
    }

    private func makeTemporaryStoreDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceCompletedHistorySafety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
