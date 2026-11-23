#if canImport(SwiftData)
import Testing
import Foundation
import SwiftData
@testable import CadenceCore
@testable import CadenceWorkoutFeatures

@Suite struct ApplicationContainerFallbackTests {
    private struct MirrorError: Error {}

    @Test func cloudKitSetupFailureFallsBackToLocalOnlyInsteadOfThrowing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cladiron-fallback-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var attempts: [Bool] = []
        _ = try CadenceStore.makeApplicationModelContainer(
            directory: dir,
            singleFactory: { url, cloudKit in
                attempts.append(cloudKit)
                if cloudKit { throw MirrorError() }
                return try CadenceStore.makeSingleModelContainer(
                    storeURL: url, cloudKitEnabled: false)
            })
        #expect(attempts == [true, false])
    }

    /// issue #779: when `makeApplicationModelContainer()` throws even after its
    /// own CloudKit-disabled retry (e.g. a corrupted/incompatible on-disk
    /// store), the phone app must not propagate that error all the way to an
    /// unconditional crash. Wiring it through `WatchStoreBootstrapPolicy` (the
    /// same quarantine → retry → in-memory-fallback mechanism the Watch app
    /// already uses) must still produce a usable container instead of
    /// throwing — this is the exact combinator `CadenceApp.init()` now uses.
    @Test func persistentContainerFailureRecoversViaQuarantineAndDegradesToInMemoryInsteadOfThrowing() throws {
        var persistentAttempts = 0
        var quarantined = false
        let policy = WatchStoreBootstrapPolicy<ModelContainer>(
            createPersistent: {
                persistentAttempts += 1
                throw MirrorError()
            },
            createInMemory: {
                try CadenceStore.makeModelContainer(inMemory: true)
            },
            quarantine: {
                quarantined = true
                return nil
            },
            seed: { _ in })

        let result = policy.open()

        #expect(persistentAttempts == 2, "must retry once after quarantine before degrading")
        #expect(quarantined)
        #expect(result.state == .degraded)
        #expect(result.container != nil, "must still produce a usable (in-memory) container instead of leaving the app with none")
    }
}

@MainActor
struct ApplicationContainerMigrationTests {
    /// The legacy single store is copied into Cladiron.store once, and the old
    /// file is retained as a rollback copy.
    @Test func legacyStoreIsCopiedIntoTheSingleApplicationStore() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cladiron-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let legacyURL = dir.appendingPathComponent(CadenceStore.legacyStoreFileName)
        let legacy = try CadenceStore.makeModelContainer(inMemory: false,
                                                         cloudKitEnabled: false,
                                                         storeURL: legacyURL)
        let legacyContext = ModelContext(legacy)
        let exercise = Exercise(name: "Row")
        let session = WorkoutSession(title: "Legacy")
        legacyContext.insert(exercise)
        legacyContext.insert(session)
        legacyContext.insert(SetEntry(weight: 40, reps: 8, session: session, exercise: exercise))
        legacyContext.insert(Person(name: "Sam"))
        try legacyContext.save()

        let container = try CadenceStore.makeApplicationModelContainer(
            directory: dir,
            singleFactory: { url, _ in
                try CadenceStore.makeSingleModelContainer(storeURL: url, cloudKitEnabled: false)
            })
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Person>()) == 1)
        #expect(FileManager.default.fileExists(atPath: legacyURL.path),
                "the old file stays as the rollback copy")
        #expect(CadenceStore.applicationStoreReady(in: dir))
    }

    /// Devices that already migrated to Local/Sync must not lose that data when
    /// the application moves back to one store.
    @Test func splitStoreIsCopiedIntoTheSingleApplicationStore() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cladiron-split-to-single-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let urls = CadenceStore.splitStoreURLs(in: dir)
        let split = try CadenceStore.makeSplitModelContainer(
            localURL: urls.local, syncURL: urls.sync, cloudKitEnabled: false)
        let splitContext = ModelContext(split)
        let exercise = Exercise(name: "Press")
        let session = WorkoutSession(title: "Split")
        let person = Person(name: "Alex")
        splitContext.insert(exercise)
        splitContext.insert(session)
        splitContext.insert(person)
        splitContext.insert(SetEntry(weight: 60, reps: 6, session: session,
                                     exercise: exercise, performedBy: person))
        try splitContext.save()

        let container = try CadenceStore.makeApplicationModelContainer(
            directory: dir,
            singleFactory: { url, _ in
                try CadenceStore.makeSingleModelContainer(storeURL: url, cloudKitEnabled: false)
            })
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Person>()) == 1)
        let restoredSession = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        let restoredExercise = try #require(try context.fetch(FetchDescriptor<Exercise>()).first)
        let added = try WorkoutRepository.addSet(to: restoredSession,
                                                 exercise: restoredExercise,
                                                 weightKg: 70, reps: 5,
                                                 in: context)
        #expect(added.exercise?.id == restoredExercise.id)
        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 2)
        #expect(FileManager.default.fileExists(atPath: urls.local.path))
        #expect(FileManager.default.fileExists(atPath: urls.sync.path))
        #expect(CadenceStore.applicationStoreReady(in: dir))
    }
}
#endif
