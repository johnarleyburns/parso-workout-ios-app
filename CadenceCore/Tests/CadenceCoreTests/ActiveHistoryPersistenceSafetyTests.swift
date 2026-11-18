import XCTest
import SwiftData
@testable import CadenceCore

/// Independent regression test for the in-progress path. A workout abandoned
/// by an app restart is still user history and must remain resumable.
@MainActor
final class ActiveHistoryPersistenceSafetyTests: XCTestCase {
    func testReopeningPersistentStorePreservesActiveWorkout() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceActiveHistorySafety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("history.store")
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_700_100_000)

        do {
            let container = try CadenceStore.makeModelContainer(inMemory: false,
                                                                cloudKitEnabled: false,
                                                                storeURL: storeURL)
            let context = ModelContext(container)
            let session = WorkoutSession(id: id, title: "Active Persistence Regression", date: start)
            session.plannedExerciseNames = ["Active Test Exercise"]
            let exercise = Exercise(name: "Active Test Exercise")
            let set = SetEntry(weight: 40, reps: 5, order: 0,
                               completedAt: start.addingTimeInterval(300),
                               session: session, exercise: exercise)
            context.insert(exercise)
            context.insert(session)
            context.insert(set)
            try context.save()
        }

        let reopened = try CadenceStore.makeModelContainer(inMemory: false,
                                                            cloudKitEnabled: false,
                                                            storeURL: storeURL)
        let context = ModelContext(reopened)
        let session = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WorkoutSession>()).first(where: { $0.id == id }))
        XCTAssertTrue(session.isResumable)
        XCTAssertNil(session.endedAt)
        XCTAssertEqual(session.plannedExerciseNames, ["Active Test Exercise"])
        XCTAssertEqual(session.orderedSets.count, 1)
    }
}
