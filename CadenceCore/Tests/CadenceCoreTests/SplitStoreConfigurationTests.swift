#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

/// H5's privacy boundary must be constructible before the app is allowed to
/// switch from the legacy single-store container.
@MainActor
struct SplitStoreConfigurationTests {
    @Test func localAndSyncConfigurationsOpenOnSeparateFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceSplitStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let container = try CadenceStore.makeSplitModelContainer(
            localURL: directory.appendingPathComponent("Local.store"),
            syncURL: directory.appendingPathComponent("Sync.store"),
            cloudKitEnabled: false)
        let context = ModelContext(container)
        let session = WorkoutSession(title: "Local history")
        let exercise = Exercise(name: "Sync exercise")
        let set = SetEntry(weight: 20, reps: 5, session: session, exercise: exercise)
        context.insert(session)
        context.insert(exercise)
        context.insert(set)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Local.store").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Sync.store").path))
    }
}
#endif
