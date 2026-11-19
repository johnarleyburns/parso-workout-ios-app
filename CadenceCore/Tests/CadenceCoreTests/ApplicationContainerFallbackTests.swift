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
#endif
