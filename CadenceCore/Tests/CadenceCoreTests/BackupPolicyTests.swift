import XCTest
@testable import CadenceCore

/// D5 decision logic, pure. No CloudKit in this test path. The named invariant
/// `test_nonEmptyLocalNeverSilentlyClobbered` guarantees a restore can never wipe a
/// user's existing training log without asking.
final class BackupPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func meta(sessions: Int = 10, schema: Int = 5, ageHours: Double = 1) -> RemoteBackupMeta {
        RemoteBackupMeta(createdAt: now.addingTimeInterval(-ageHours * 3600),
                         sessionCount: sessions,
                         schemaVersion: schema)
    }

    // MARK: shouldBackUp

    func testNeverBackedUpWithLocalChangesIsDue() {
        XCTAssertTrue(BackupPolicy.shouldBackUp(
            lastBackupAt: nil,
            lastLocalChangeAt: now.addingTimeInterval(-3600),
            now: now))
    }

    func testNothingChangedLocallyIsNotDue() {
        // No local change ever recorded → nothing worth backing up.
        XCTAssertFalse(BackupPolicy.shouldBackUp(
            lastBackupAt: nil,
            lastLocalChangeAt: nil,
            now: now))
    }

    func testNoChangesSinceLastBackupIsNotDue() {
        let lastBackup = now.addingTimeInterval(-BackupPolicy.minimumInterval * 2)
        let lastChange = lastBackup.addingTimeInterval(-3600) // changed BEFORE the backup
        XCTAssertFalse(BackupPolicy.shouldBackUp(
            lastBackupAt: lastBackup,
            lastLocalChangeAt: lastChange,
            now: now))
    }

    func testChangedButWithinIntervalIsNotDue() {
        let lastBackup = now.addingTimeInterval(-3600) // 1h ago, < 24h
        let lastChange = now.addingTimeInterval(-1800)  // changed 30m ago
        XCTAssertFalse(BackupPolicy.shouldBackUp(
            lastBackupAt: lastBackup,
            lastLocalChangeAt: lastChange,
            now: now))
    }

    func testChangedAndIntervalElapsedIsDue() {
        let lastBackup = now.addingTimeInterval(-BackupPolicy.minimumInterval - 3600)
        let lastChange = now.addingTimeInterval(-1800) // changed since the backup
        XCTAssertTrue(BackupPolicy.shouldBackUp(
            lastBackupAt: lastBackup,
            lastLocalChangeAt: lastChange,
            now: now))
    }

    func testExactlyAtIntervalBoundaryIsDue() {
        let lastBackup = now.addingTimeInterval(-BackupPolicy.minimumInterval)
        let lastChange = now.addingTimeInterval(-60)
        XCTAssertTrue(BackupPolicy.shouldBackUp(
            lastBackupAt: lastBackup,
            lastLocalChangeAt: lastChange,
            now: now))
    }

    // MARK: restoreDecision

    func testEmptyLocalWithRemoteAutoRestores() {
        XCTAssertEqual(
            BackupPolicy.restoreDecision(localSessionCount: 0, remote: meta()),
            .autoRestore(meta()))
    }

    func test_nonEmptyLocalNeverSilentlyClobbered() {
        // The invariant: any local data present → we must ASK, never auto-restore.
        let decision = BackupPolicy.restoreDecision(localSessionCount: 3, remote: meta())
        XCTAssertEqual(decision, .offerRestore(meta()))
        if case .autoRestore = decision {
            XCTFail("must never silently overwrite existing local data")
        }
    }

    func testNoRemoteIsNone() {
        XCTAssertEqual(
            BackupPolicy.restoreDecision(localSessionCount: 0, remote: nil),
            .none)
        XCTAssertEqual(
            BackupPolicy.restoreDecision(localSessionCount: 5, remote: nil),
            .none)
    }

    func testOlderSchemaRemoteStillDecidable() {
        // A v1 backup (schemaVersion 1) still yields a valid decision — DataExport
        // decodes v1–v4 exports, so the policy must not gate on schema version.
        let old = meta(sessions: 8, schema: 1)
        XCTAssertEqual(
            BackupPolicy.restoreDecision(localSessionCount: 0, remote: old),
            .autoRestore(old))
    }
}
