#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

@MainActor
struct StoreMigrationRuntimeTests {
    @Test func migrationCopiesBothBoundariesAndWritesRollbackArtifact() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyURL = directory.appendingPathComponent("default.store")
        let localURL = directory.appendingPathComponent("Local.store")
        let syncURL = directory.appendingPathComponent("Sync.store")
        let stateURL = directory.appendingPathComponent(StoreMigrationRuntime.stateFileName)
        let snapshotURL = directory.appendingPathComponent(StoreMigrationRuntime.snapshotFileName)

        try seedLegacyStore(at: legacyURL)

        let result = try StoreMigrationRuntime.migrate(
            legacyURL: legacyURL, localURL: localURL, syncURL: syncURL,
            stateURL: stateURL, snapshotURL: snapshotURL, cloudKitEnabled: false,
            now: Date(timeIntervalSince1970: 100))

        #expect(result.oldCounts == StoreMigrationCounts(sessions: 1, ownerSets: 1,
                                                               cardio: 1, assessments: 1))
        #expect(result.newCounts == result.oldCounts)
        #expect(FileManager.default.fileExists(atPath: snapshotURL.path))
        #expect(!FileManager.default.fileExists(atPath: directory
            .appendingPathComponent(StoreMigrationRuntime.readyMarkerFileName).path))

        let split = try CadenceStore.makeSplitModelContainer(
            localURL: localURL, syncURL: syncURL, cloudKitEnabled: false)
        let restored = ModelContext(split)
        #expect(try restored.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
        #expect(try restored.fetchCount(FetchDescriptor<Exercise>()) == 1)
        #expect(try restored.fetchCount(FetchDescriptor<SetEntry>()) == 1)
        #expect(try restored.fetchCount(FetchDescriptor<Person>()) == 1)
    }

    /// The interactive upgrade is gone: a pre-split store is copied at first
    /// launch, the split store becomes selectable immediately, and the old file
    /// is retained rather than deleted.
    @Test func launchMigrationWritesMarkersAndKeepsTheLegacyFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceLaunchMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyURL = directory.appendingPathComponent("default.store")
        let localURL = directory.appendingPathComponent("Local.store")
        let syncURL = directory.appendingPathComponent("Sync.store")
        let stateURL = directory.appendingPathComponent(StoreMigrationRuntime.stateFileName)
        let snapshotURL = directory.appendingPathComponent(StoreMigrationRuntime.snapshotFileName)

        try seedLegacyStore(at: legacyURL)

        try StoreMigrationRuntime.migrateLegacyStoreAtLaunch(
            legacyURL: legacyURL, localURL: localURL, syncURL: syncURL,
            stateURL: stateURL, snapshotURL: snapshotURL)

        #expect(FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(FileManager.default.fileExists(atPath: localURL.path))
        #expect(FileManager.default.fileExists(atPath: syncURL.path))
        #expect(FileManager.default.fileExists(atPath: snapshotURL.path))
        #expect(FileManager.default.fileExists(atPath: directory
            .appendingPathComponent(StoreMigrationRuntime.readyMarkerFileName).path))
        #expect(FileManager.default.fileExists(atPath: directory
            .appendingPathComponent(StoreMigrationRuntime.pendingHealthBackfillFileName).path))
    }

    private func seedLegacyStore(at url: URL) throws {
        let legacy = try CadenceStore.makeModelContainer(inMemory: false,
                                                         cloudKitEnabled: false,
                                                         storeURL: url)
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
    }
}
#endif
