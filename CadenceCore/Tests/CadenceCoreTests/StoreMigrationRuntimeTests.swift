import XCTest
import SwiftData
@testable import CadenceCore

@MainActor
final class StoreMigrationRuntimeTests: XCTestCase {
    func testMigrationCopiesBothBoundariesAndWritesRollbackArtifact() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyURL = directory.appendingPathComponent("default.store")
        let localURL = directory.appendingPathComponent("Local.store")
        let syncURL = directory.appendingPathComponent("Sync.store")
        let stateURL = directory.appendingPathComponent(StoreMigrationRuntime.stateFileName)
        let snapshotURL = directory.appendingPathComponent(StoreMigrationRuntime.snapshotFileName)

        let legacy = try CadenceStore.makeModelContainer(inMemory: false,
                                                         cloudKitEnabled: false,
                                                         storeURL: legacyURL)
        let context = ModelContext(legacy)
        let exercise = Exercise(name: "Bench Press")
        let session = WorkoutSession(title: "Push")
        context.insert(exercise)
        context.insert(session)
        context.insert(SetEntry(weight: 100, reps: 5, session: session, exercise: exercise))
        context.insert(Person(name: "Audrey"))
        context.insert(CardioWorkout(type: .run))
        context.insert(Assessment(kind: .vo2maxField, value: 40))
        try context.save()

        let result = try StoreMigrationRuntime.migrate(
            legacyURL: legacyURL, localURL: localURL, syncURL: syncURL,
            stateURL: stateURL, snapshotURL: snapshotURL, cloudKitEnabled: false,
            now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(result.oldCounts, StoreMigrationCounts(sessions: 1, ownerSets: 1,
                                                               cardio: 1, assessments: 1))
        XCTAssertEqual(result.newCounts, result.oldCounts)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory
            .appendingPathComponent(StoreMigrationRuntime.readyMarkerFileName).path))
        try StoreMigrationRuntime.markHealthBackfillQueued(stateURL: stateURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory
            .appendingPathComponent(StoreMigrationRuntime.readyMarkerFileName).path))

        let split = try CadenceStore.makeSplitModelContainer(
            localURL: localURL, syncURL: syncURL, cloudKitEnabled: false)
        let restored = ModelContext(split)
        XCTAssertEqual(try restored.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try restored.fetchCount(FetchDescriptor<Exercise>()), 1)
        XCTAssertEqual(try restored.fetchCount(FetchDescriptor<SetEntry>()), 1)
        XCTAssertEqual(try restored.fetchCount(FetchDescriptor<Person>()), 1)
    }
}
