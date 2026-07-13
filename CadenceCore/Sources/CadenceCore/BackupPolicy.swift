import Foundation

/// Metadata describing a backup that lives in the user's private CloudKit database.
/// The payload itself is the existing `CadenceExport` v5 `.json.gz` blob — this is
/// only the lightweight header used to decide whether to back up or restore.
public struct RemoteBackupMeta: Sendable, Equatable {
    public let createdAt: Date
    public let sessionCount: Int
    public let schemaVersion: Int

    public init(createdAt: Date, sessionCount: Int, schemaVersion: Int) {
        self.createdAt = createdAt
        self.sessionCount = sessionCount
        self.schemaVersion = schemaVersion
    }
}

/// What to do with a remote backup on launch. `autoRestore` is only ever returned
/// when the local store is empty — a fresh install — so restoring can never clobber
/// user data. A non-empty local store always defers to the user (`offerRestore`).
public enum RestoreDecision: Sendable, Equatable {
    case none
    case offerRestore(RemoteBackupMeta)   // local data exists — ask first
    case autoRestore(RemoteBackupMeta)    // fresh install — safe to restore
}

/// Pure backup/restore decision logic (D5). No CloudKit in the test path — the
/// `CloudBackupService` (app layer) owns the actual `CKContainer` work and calls
/// these to decide *whether* to act.
public enum BackupPolicy {

    /// Don't back up more than once a day. Backup is insurance, not real-time sync;
    /// a daily opportunistic snapshot is enough to prevent "it deleted my log."
    public static let minimumInterval: TimeInterval = 24 * 3600

    /// True when a new backup is due: never backed up (and there is something to
    /// back up), or the interval has elapsed since the last backup AND the local
    /// store changed since then.
    public static func shouldBackUp(lastBackupAt: Date?,
                                    lastLocalChangeAt: Date?,
                                    now: Date) -> Bool {
        // Nothing has ever changed locally → nothing worth backing up.
        guard let lastChange = lastLocalChangeAt else { return false }

        guard let lastBackup = lastBackupAt else {
            // Never backed up, but local data exists → due.
            return true
        }

        // No local changes since the last backup → not due.
        guard lastChange > lastBackup else { return false }

        // Changed since the last backup: due only once the interval has elapsed.
        return now.timeIntervalSince(lastBackup) >= minimumInterval
    }

    /// Decide what to do with a remote backup, given how much local data exists.
    /// Empty local + a remote backup → safe to auto-restore. Any local data →
    /// never silently clobber it; offer the choice to the user.
    public static func restoreDecision(localSessionCount: Int,
                                       remote: RemoteBackupMeta?) -> RestoreDecision {
        guard let remote else { return .none }
        if localSessionCount == 0 {
            return .autoRestore(remote)
        }
        return .offerRestore(remote)
    }
}
