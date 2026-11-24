#if canImport(SwiftData)
import Foundation
import SwiftData

/// The file-backed H5 adapter. The planner owns ordering; this type owns only
/// the platform-neutral copy, verification, resume marker, and rollback
/// artifact. HealthKit backfill is deliberately performed by the app target
/// after the local copy is verified, because Core must not import HealthKit.
public enum StoreMigrationRuntime {
    public static let stateFileName = "StoreMigrationProgress.json"
    public static let snapshotFileName = "pre-split-native-db-v8.json"
    public static let singleStoreSnapshotFileName = "pre-single-store-native-db-v9.json"
    public static let readyMarkerFileName = "split-store.ready"
    public static let singleStoreReadyMarkerFileName = "single-store.ready"
    /// Set when the launch copy ran, so the app can queue the same HealthKit
    /// backfill the old interactive upgrade used to queue. HealthKit
    /// identifiers make that backfill idempotent.
    public static let pendingHealthBackfillFileName = "LegacyStoreHealthBackfill.pending"

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
    public static func migrate(legacyURL: URL, localURL: URL, syncURL: URL,
                               stateURL: URL, snapshotURL: URL,
                               now: Date = Date()) throws -> Result {
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            throw Error.legacyStoreMissing
        }

        try createParentDirectory(for: stateURL)
        try createParentDirectory(for: snapshotURL)

        let legacy = try CadenceStore.makeModelContainer(inMemory: false,
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
            localURL: localURL, syncURL: syncURL)
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

    /// One-time upgrade for an install that still has the pre-split
    /// `default.store`. Runs before the first split container is opened. The
    /// copy is local-only and never depends on a cloud account.
    public static func migrateLegacyStoreAtLaunch(legacyURL: URL, localURL: URL,
                                                  syncURL: URL, stateURL: URL,
                                                  snapshotURL: URL,
                                                  now: Date = Date()) throws {
        _ = try migrate(legacyURL: legacyURL, localURL: localURL, syncURL: syncURL,
                        stateURL: stateURL, snapshotURL: snapshotURL, now: now)
        try writeReadyMarker(stateURL: stateURL)
        // The old interactive upgrade queued HealthKit backups before switching
        // stores. Keep that behavior, one launch later, without making the
        // launch copy depend on Health authorization.
        let pending = stateURL.deletingLastPathComponent()
            .appendingPathComponent(pendingHealthBackfillFileName)
        // Best-effort: the local copy is already safe and marked ready, and a
        // marker write must never turn a successful migration into a launch
        // failure (which would quarantine the new stores).
        try? Data("pending\n".utf8).write(to: pending, options: .atomic)
    }

    private static func writeReadyMarker(stateURL: URL) throws {
        let markerURL = stateURL.deletingLastPathComponent()
            .appendingPathComponent(readyMarkerFileName)
        try Data("ready\n".utf8).write(to: markerURL, options: .atomic)
    }

    /// Copies any pre-`Cladiron.store` layout (the legacy single store or the
    /// later Local/Sync pair) into the current single store. The current store
    /// must be single because SwiftData cannot encode a set's Exercise
    /// relationship when the two models live in different store configurations.
    /// Old files are left untouched as rollback copies.
    public static func migrateToSingleStore(
        directory: URL,
        singleURL: URL,
        stateURL: URL,
        snapshotURL: URL,
        now: Date = Date()
    ) throws {
        let fm = FileManager.default
        let legacyURL = CadenceStore.legacyStoreURL(in: directory)
        let split = CadenceStore.splitStoreURLs(in: directory)
        let hasSplit = CadenceStore.hasSplitStoreFiles(in: directory, fileManager: fm)
        let hasLegacy = fm.fileExists(atPath: legacyURL.path)

        guard hasSplit || hasLegacy else {
            try createParentDirectory(for: singleURL)
            try writeSingleStoreReadyMarker(stateURL: stateURL)
            return
        }

        var sourceContainer: ModelContainer?
        var sourceContext: ModelContext?
        var archive: ExportNativeDatabase?
        if hasSplit,
           let container = try? CadenceStore.makeSplitModelContainer(
               localURL: split.local, syncURL: split.sync) {
            let context = ModelContext(container)
            let built = try? NativeDatabaseExport.build(from: context)
            let sourceCounts = try? counts(in: context)
            // An empty split pair can be left behind by a failed earlier launch;
            // prefer the legacy copy when it still has data.
            if let built, let sourceCounts,
               sourceCounts != StoreMigrationCounts() || !hasLegacy {
                sourceContainer = container
                sourceContext = context
                archive = built
            }
        }
        if archive == nil, hasLegacy,
           let container = try? CadenceStore.makeModelContainer(
               inMemory: false, storeURL: legacyURL) {
            let context = ModelContext(container)
            sourceContainer = container
            sourceContext = context
            archive = try NativeDatabaseExport.build(from: context)
        }
        guard let sourceContext, let archive else {
            throw Error.legacyStoreMissing
        }

        try createParentDirectory(for: singleURL)
        try createParentDirectory(for: snapshotURL)
        do {
            try JSONEncoder().encode(archive).write(to: snapshotURL, options: .atomic)
        } catch {
            throw Error.snapshotWriteFailed
        }

        let destination = try CadenceStore.makeSingleModelContainer(
            storeURL: singleURL)
        let destinationContext = ModelContext(destination)
        _ = sourceContainer
        _ = try NativeDatabaseExport.merge(archive, in: destinationContext)

        let oldCounts = try counts(in: sourceContext)
        let newCounts = try counts(in: destinationContext)
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
        try writeSingleStoreReadyMarker(stateURL: stateURL)

        let pending = stateURL.deletingLastPathComponent()
            .appendingPathComponent(pendingHealthBackfillFileName)
        try? Data("pending\n".utf8).write(to: pending, options: .atomic)
    }

    private static func writeSingleStoreReadyMarker(stateURL: URL) throws {
        let markerURL = stateURL.deletingLastPathComponent()
            .appendingPathComponent(singleStoreReadyMarkerFileName)
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
#endif
