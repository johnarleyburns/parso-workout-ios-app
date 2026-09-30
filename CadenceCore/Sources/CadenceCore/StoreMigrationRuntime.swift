import Foundation
import SwiftData

/// The file-backed H5 adapter. The planner owns ordering; this type owns only
/// the platform-neutral copy, verification, resume marker, and rollback
/// artifact. HealthKit backfill is deliberately performed by the app target
/// after the local copy is verified, because Core must not import HealthKit.
public enum StoreMigrationRuntime {
    public static let stateFileName = "StoreMigrationProgress.json"
    public static let snapshotFileName = "pre-split-native-db-v8.json"
    public static let readyMarkerFileName = "split-store.ready"

    public enum Error: Swift.Error, Equatable, Sendable {
        case legacyStoreMissing
        case snapshotWriteFailed
        case verificationMismatch([String])
        case retentionNotElapsed(Date)
        case purgeConfirmationRequired
        case migrationNotComplete
    }

    public struct Result: Equatable, Sendable {
        public let progress: StoreMigrationProgress
        public let oldCounts: StoreMigrationCounts
        public let newCounts: StoreMigrationCounts
        public let snapshotURL: URL

        public init(progress: StoreMigrationProgress,
                    oldCounts: StoreMigrationCounts,
                    newCounts: StoreMigrationCounts,
                    snapshotURL: URL) {
            self.progress = progress
            self.oldCounts = oldCounts
            self.newCounts = newCounts
            self.snapshotURL = snapshotURL
        }
    }

    /// Copies the legacy store by stable IDs into the split container. Every
    /// step is safe to rerun: the archive is regenerated, merge is timestamp
    /// aware, and the old store is never touched by this method.
    @MainActor
    public static func migrate(legacyURL: URL, localURL: URL, syncURL: URL,
                               stateURL: URL, snapshotURL: URL,
                               cloudKitEnabled: Bool = true,
                               now: Date = Date()) throws -> Result {
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            throw Error.legacyStoreMissing
        }

        try createParentDirectory(for: stateURL)
        try createParentDirectory(for: snapshotURL)

        let legacy = try CadenceStore.makeModelContainer(inMemory: false,
                                                         cloudKitEnabled: false,
                                                         storeURL: legacyURL)
        let oldContext = ModelContext(legacy)
        let archive = try NativeDatabaseExport.build(from: oldContext)
        let snapshotData = try JSONEncoder().encode(archive)
        do {
            try snapshotData.write(to: snapshotURL, options: .atomic)
        } catch {
            throw Error.snapshotWriteFailed
        }

        let split = try CadenceStore.makeSplitModelContainer(
            localURL: localURL, syncURL: syncURL, cloudKitEnabled: cloudKitEnabled)
        let splitContext = ModelContext(split)
        _ = try NativeDatabaseExport.merge(archive, in: splitContext)

        let oldCounts = try counts(in: oldContext)
        let newCounts = try counts(in: splitContext)
        let mismatches = StoreMigrationPlanner.countMismatches(old: oldCounts,
                                                               new: newCounts)
        guard mismatches.isEmpty else {
            throw Error.verificationMismatch(mismatches)
        }

        let retainedUntil = now.addingTimeInterval(30 * 24 * 60 * 60)
        let progress = StoreMigrationProgress(
            completed: [.snapshot, .copy, .verify, .switchStore, .retainOldCopy],
            snapshotCreated: true,
            oldCopyRetainedUntil: retainedUntil,
            purgeConfirmed: false)
        try write(progress, to: stateURL)
        return Result(progress: progress, oldCounts: oldCounts,
                      newCounts: newCounts, snapshotURL: snapshotURL)
    }

    /// Completes the app-owned portion of migration after every HealthKit
    /// backfill job has been durably queued. Only then may the app select the
    /// split container on its next launch.
    @MainActor
    public static func markHealthBackfillQueued(stateURL: URL) throws {
        guard var progress = try loadProgress(from: stateURL),
              progress.completed.contains(.snapshot),
              progress.completed.contains(.copy),
              progress.completed.contains(.verify),
              progress.completed.contains(.switchStore) else {
            throw Error.migrationNotComplete
        }
        progress.completed.insert(.preflight)
        progress.completed.insert(.healthBackfill)
        try write(progress, to: stateURL)
        let markerURL = stateURL.deletingLastPathComponent()
            .appendingPathComponent(readyMarkerFileName)
        try Data("ready\n".utf8).write(to: markerURL, options: .atomic)
    }

    public static func loadProgress(from stateURL: URL) throws -> StoreMigrationProgress? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        return try JSONDecoder().decode(StoreMigrationProgress.self,
                                        from: Data(contentsOf: stateURL))
    }

    /// Deletes only the validated legacy store files, and only after the
    /// retention window plus an explicit confirmation have both passed.
    public static func purgeLegacyCopy(legacyURL: URL, stateURL: URL,
                                       now: Date = Date()) throws {
        guard let progress = try loadProgress(from: stateURL),
              progress.completed.contains(.complete) ||
              progress.completed.contains(.purgeOldCopy) else {
            throw Error.migrationNotComplete
        }
        guard let retainedUntil = progress.oldCopyRetainedUntil else {
            throw Error.migrationNotComplete
        }
        guard now >= retainedUntil else { throw Error.retentionNotElapsed(retainedUntil) }
        guard progress.purgeConfirmed else { throw Error.purgeConfirmationRequired }

        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: legacyURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func write(_ progress: StoreMigrationProgress, to url: URL) throws {
        try JSONEncoder().encode(progress).write(to: url, options: .atomic)
    }

    private static func createParentDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
    }

    private static func counts(in context: ModelContext) throws -> StoreMigrationCounts {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let ownerSets = try context.fetch(FetchDescriptor<SetEntry>())
            .filter(\.isOwnerSet).count
        return StoreMigrationCounts(
            sessions: sessions.count,
            ownerSets: ownerSets,
            cardio: try context.fetchCount(FetchDescriptor<CardioWorkout>()),
            assessments: try context.fetchCount(FetchDescriptor<Assessment>()))
    }
}
