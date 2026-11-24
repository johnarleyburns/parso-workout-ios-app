#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

/// Independent file-level regression test. Reopening an existing store must
/// leave the store file present and non-empty; a missing-file failure is easier
/// to diagnose than a later empty-history symptom.
@MainActor
struct StoreFilePersistenceSafetyTests {
    @Test func reopeningStoreLeavesPersistentFileIntact() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceStoreFileSafety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("history.store")

        do {
            let container = try CadenceStore.makeModelContainer(inMemory: false,
                                                                storeURL: storeURL)
            let context = ModelContext(container)
            context.insert(WorkoutSession(title: "File Safety Regression"))
            try context.save()
        }

        let sizeBefore = try #require(
            FileManager.default.attributesOfItem(atPath: storeURL.path)[.size] as? NSNumber).int64Value
        #expect(sizeBefore > 0)

        _ = try CadenceStore.makeModelContainer(inMemory: false,
                                                storeURL: storeURL)

        #expect(FileManager.default.fileExists(atPath: storeURL.path),
                      "Opening an existing store must never remove its primary file")
        let sizeAfter = try #require(
            FileManager.default.attributesOfItem(atPath: storeURL.path)[.size] as? NSNumber).int64Value
        #expect(sizeAfter > 0)
    }
}
#endif
