import XCTest
import SwiftData
@testable import CadenceCore

/// Independent file-level regression test. Reopening an existing store must
/// leave the store file present and non-empty; a missing-file failure is easier
/// to diagnose than a later empty-history symptom.
@MainActor
final class StoreFilePersistenceSafetyTests: XCTestCase {
    func testReopeningStoreLeavesPersistentFileIntact() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceStoreFileSafety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("history.store")

        do {
            let container = try CadenceStore.makeModelContainer(inMemory: false,
                                                                cloudKitEnabled: false,
                                                                storeURL: storeURL)
            let context = ModelContext(container)
            context.insert(WorkoutSession(title: "File Safety Regression"))
            try context.save()
        }

        let sizeBefore = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: storeURL.path)[.size] as? NSNumber).int64Value
        XCTAssertGreaterThan(sizeBefore, 0)

        _ = try CadenceStore.makeModelContainer(inMemory: false,
                                                cloudKitEnabled: false,
                                                storeURL: storeURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path),
                      "Opening an existing store must never remove its primary file")
        let sizeAfter = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: storeURL.path)[.size] as? NSNumber).int64Value
        XCTAssertGreaterThan(sizeAfter, 0)
    }
}
