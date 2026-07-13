import Foundation
import SwiftData
import CloudKit
import CadenceCore
import CadenceFeatures
import os

/// Automatic backup + restore of the existing `CadenceExport` `.json.gz` blob to the
/// user's **private** CloudKit database (revenue Phase 5, D5).
///
/// This is NOT live SwiftData↔CloudKit sync. It reuses `DataExport` /
/// `WorkoutRepository.merge` wholesale, leaves the SwiftData schema untouched (no
/// migration risk), and — crucially — keeps the **Data Not Collected** privacy
/// label: the blob lives in the *user's own* iCloud, Apple is the processor, and
/// Cladiron never sees it.
///
/// All the *decision* logic (when to back up, whether to auto-restore) lives in the
/// pure, unit-tested `BackupPolicy`; this service only performs the CloudKit I/O it
/// tells us to. It never blocks a workout — backup is opportunistic and off the
/// critical path.
@Observable
@MainActor
final class CloudBackupService {

    enum Status: Equatable {
        case idle
        case backingUp
        case restoring
        case unavailable       // no iCloud account / disabled
        case failed(String)
    }

    private(set) var status: Status = .idle

    /// The record type + fixed record name. A single record per user holds the
    /// latest backup; we overwrite it rather than accumulate history.
    private static let recordType = "CladironBackup"
    private static let recordName = "latest"
    private static let assetKey = "payload"
    private static let createdAtKey = "createdAt"
    private static let sessionCountKey = "sessionCount"
    private static let schemaVersionKey = "schemaVersion"

    private let container: ModelContainer
    private let cloud: CKContainer
    private let logger = Logger(subsystem: "com.cladiron.cadence", category: "backup")

    init(container: ModelContainer, cloudContainer: CKContainer = .default()) {
        self.container = container
        self.cloud = cloudContainer
    }

    private var database: CKDatabase { cloud.privateCloudDatabase }
    private var recordID: CKRecord.ID { CKRecord.ID(recordName: Self.recordName) }

    // MARK: Availability

    /// True when the user is signed into iCloud and the account is usable.
    func iCloudAvailable() async -> Bool {
        do { return try await cloud.accountStatus() == .available }
        catch { return false }
    }

    // MARK: Backup

    /// Back up now if `BackupPolicy` says it's due (or `force`). Reuses the exact
    /// export blob format `ExportView` produces. Safe to call on launch / scene
    /// activation; it no-ops quickly when not due.
    func backUpIfNeeded(settings: AppSettings, force: Bool = false, now: Date = Date()) async {
        guard settings.iCloudBackupEnabled else { return }
        guard force || BackupPolicy.shouldBackUp(lastBackupAt: settings.lastBackupAt,
                                                 lastLocalChangeAt: settings.lastLocalChangeAt,
                                                 now: now) else { return }
        guard await iCloudAvailable() else {
            status = .unavailable
            return
        }

        status = .backingUp
        let coachDTO = settings.coachPreferenceProfile.exportDTO
        let prefs = settings.exportPreferences()

        do {
            let (data, sessionCount, schemaVersion) = try await buildBlob(coachDTO: coachDTO, prefs: prefs)
            // Nothing to back up (empty store) — don't create an empty record.
            guard sessionCount > 0 || data.count > 0 else { status = .idle; return }
            try await upload(data: data, sessionCount: sessionCount, schemaVersion: schemaVersion, now: now)
            settings.lastBackupAt = now
            status = .idle
        } catch {
            logger.error("iCloud backup failed: \(error.localizedDescription)")
            status = .failed(error.localizedDescription)
        }
    }

    private func buildBlob(coachDTO: ExportCoachPreferences?,
                           prefs: ExportPreferences) async throws -> (Data, Int, Int) {
        let container = self.container
        return try await Task.detached(priority: .utility) {
            let ctx = ModelContext(container)
            let export = try WorkoutRepository.buildExport(ctx, coachPreferences: coachDTO, preferences: prefs)
            let raw = try DataExport.encodeJSON(export)
            let gz = try DataCompression.gzip(raw)
            return (gz, export.sessions.count, export.version)
        }.value
    }

    private func upload(data: Data, sessionCount: Int, schemaVersion: Int, now: Date) async throws {
        // Write the blob to a temp file so CKAsset can stream it.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cladiron-backup-\(UUID().uuidString).json.gz")
        try data.write(to: tmp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Fetch-or-create the single latest record, then overwrite its fields.
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }
        record[Self.assetKey] = CKAsset(fileURL: tmp)
        record[Self.createdAtKey] = now as CKRecordValue
        record[Self.sessionCountKey] = sessionCount as CKRecordValue
        record[Self.schemaVersionKey] = schemaVersion as CKRecordValue

        _ = try await database.save(record)
    }

    // MARK: Restore

    /// Fetch the remote backup's metadata (no payload download), if one exists.
    func remoteBackupMeta() async -> RemoteBackupMeta? {
        guard await iCloudAvailable() else { return nil }
        guard let record = try? await database.record(for: recordID) else { return nil }
        let created = record[Self.createdAtKey] as? Date ?? Date.distantPast
        let sessions = record[Self.sessionCountKey] as? Int ?? 0
        let schema = record[Self.schemaVersionKey] as? Int ?? 0
        return RemoteBackupMeta(createdAt: created, sessionCount: sessions, schemaVersion: schema)
    }

    /// Decide what to do with a remote backup given the current local store.
    func restoreDecision(now: Date = Date()) async -> RestoreDecision {
        let local = localSessionCount()
        let remote = await remoteBackupMeta()
        return BackupPolicy.restoreDecision(localSessionCount: local, remote: remote)
    }

    /// Download the remote backup and merge it into the local store, applying
    /// preferences. Returns the number of workouts merged. Never clobbers — `merge`
    /// dedups by stable UUID, so re-restoring is idempotent.
    @discardableResult
    func restore(settings: AppSettings) async throws -> Int {
        guard await iCloudAvailable() else {
            status = .unavailable
            throw CloudBackupError.unavailable
        }
        status = .restoring
        defer { if case .restoring = status { status = .idle } }

        let record = try await database.record(for: recordID)
        guard let asset = record[Self.assetKey] as? CKAsset, let url = asset.fileURL else {
            throw CloudBackupError.emptyBackup
        }
        let data = try Data(contentsOf: url)
        let container = self.container
        let (added, prefs) = try await Task.detached(priority: .userInitiated) {
            let export = try DataExport.decodeAny(data)
            let ctx = ModelContext(container)
            let added = try WorkoutRepository.merge(export, in: ctx)
            return (added, export.preferences)
        }.value
        if let prefs { settings.applyImportedPreferences(prefs) }
        status = .idle
        return added
    }

    // MARK: Local store

    private func localSessionCount() -> Int {
        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<WorkoutSession>()
        return (try? ctx.fetchCount(descriptor)) ?? 0
    }
}

enum CloudBackupError: LocalizedError {
    case unavailable
    case emptyBackup

    var errorDescription: String? {
        switch self {
        case .unavailable: return "iCloud isn't available. Sign in to iCloud in Settings to back up."
        case .emptyBackup: return "The iCloud backup is empty."
        }
    }
}
