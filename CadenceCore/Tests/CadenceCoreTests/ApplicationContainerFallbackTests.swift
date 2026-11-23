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
            splitFactory: { local, sync, cloudKit in
                attempts.append(cloudKit)
                if cloudKit { throw MirrorError() }
                return try CadenceStore.makeSplitModelContainer(
                    localURL: local, syncURL: sync, cloudKitEnabled: false)
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
    /// Retiring the legacy fallback must not strand an upgraded install: the
    /// first launch copies the old single store into Local/Sync, marks the
    /// split store ready, and leaves the old file untouched as a rollback copy.
    @Test func preSplitStoreIsCopiedIntoTheSplitStoreOnFirstLaunch() throws {
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
            splitFactory: { local, sync, _ in
                try CadenceStore.makeSplitModelContainer(
                    localURL: local, syncURL: sync, cloudKitEnabled: false)
            })
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Person>()) == 1)
        #expect(FileManager.default.fileExists(atPath: legacyURL.path),
                "the old file stays as the rollback copy")
        #expect(CadenceStore.splitStoreReady(in: dir))
    }

}
#endif
