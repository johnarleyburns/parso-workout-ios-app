#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

/// Regression coverage for the 2026-11 store-recovery incident: a store left
/// in a Recovery-* quarantine folder must be merged back into the live store
/// without touching or deleting the old file.
@MainActor
struct StoreRecoveryTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CladironStoreRecovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeRecoveryStore(in directory: URL, title: String) throws {
        let recovery = directory.appendingPathComponent("Recovery-TEST", isDirectory: true)
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        let storeURL = recovery.appendingPathComponent(CadenceStore.applicationStoreFileName)
        let container = try CadenceStore.makeSingleModelContainer(storeURL: storeURL)
        let context = ModelContext(container)
        let session = WorkoutSession(title: title, date: Date(timeIntervalSince1970: 1_700_000_000),
                                     endedAt: Date(timeIntervalSince1970: 1_700_003_600))
        context.insert(session)
        try context.save()
    }

    @Test func mergesAQuarantinedStoreIntoTheLiveStore() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try makeRecoveryStore(in: directory, title: "Recovered Push Day")
        let live = try CadenceStore.makeApplicationModelContainer(directory: directory)
        let liveContext = ModelContext(live)
        #expect(try liveContext.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)

        let report = StoreRecovery.recover(into: live, directory: directory)
        #expect(report.errors.isEmpty)
        #expect(report.recoveredAny)
        #expect(report.currentSessionsAfter == 1)
        #expect(try liveContext.fetch(FetchDescriptor<WorkoutSession>()).first?.title == "Recovered Push Day")
        // The source is preserved for rollback.
        #expect(FileManager.default.fileExists(atPath: directory
            .appendingPathComponent("Recovery-TEST")
            .appendingPathComponent(CadenceStore.applicationStoreFileName).path))
    }

    @Test func autoRecoveryRunsOnlyForAnEmptyLiveStore() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try makeRecoveryStore(in: directory, title: "Recovered Legs")
        let live = try CadenceStore.makeApplicationModelContainer(directory: directory)
        let report = StoreRecovery.autoRecoverIfNeeded(container: live, directory: directory)
        #expect(report?.recoveredAny == true)
        #expect(FileManager.default.fileExists(atPath: directory
            .appendingPathComponent(StoreRecovery.autoMarkerFileName).path))
        #expect(try ModelContext(live).fetchCount(FetchDescriptor<WorkoutSession>()) == 1)

        // A second launch must not merge the same source again.
        #expect(StoreRecovery.autoRecoverIfNeeded(container: live, directory: directory) == nil)
    }
}
#endif
