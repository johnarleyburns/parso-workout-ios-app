import Testing
import Foundation
import SwiftData
@testable import CadenceCore

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
}
