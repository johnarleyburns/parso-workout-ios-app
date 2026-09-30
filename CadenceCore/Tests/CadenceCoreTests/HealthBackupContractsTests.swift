import XCTest
@testable import CadenceCore

final class HealthBackupContractsTests: XCTestCase {
    func testOwnerSetMetadataIsTypedAndExcludesPartnerIdentity() {
        let exercise = Exercise(name: "Cable Row")
        let set = SetEntry(weight: 57, reps: 8, rpe: 8, note: "smooth", exercise: exercise)
        let reference = CrossStoreReferenceResolver().exercise(for: set, exercises: [exercise])
        let metadata = CladironHealthBackup.ownerSetMetadata(for: set, exercise: reference)

        XCTAssertTrue(CladironHealthBackup.isSupported(metadata))
        XCTAssertEqual(metadata[CladironHealthBackup.syncIdentifierKey], set.id.uuidString)
        XCTAssertEqual(metadata[CladironHealthBackup.exerciseNameKey], "Cable Row")
        XCTAssertEqual(metadata[CladironHealthBackup.weightKgKey], "57.0")
        XCTAssertEqual(metadata[CladironHealthBackup.repsKey], "8")
        XCTAssertNil(metadata[CladironHealthBackup.performerKey])
    }

    func testSyncVersionIsMonotonicInMilliseconds() {
        let first = Date(timeIntervalSince1970: 10)
        let second = Date(timeIntervalSince1970: 10.001)
        XCTAssertLessThan(CladironHealthBackup.syncVersion(for: first),
                          CladironHealthBackup.syncVersion(for: second))
    }

    func testRestorePlannerKeepsEqualOrOlderLocalData() {
        let now = Date()
        let local = HealthRestoreVersion(updatedAt: now)
        XCTAssertEqual(HealthRestorePlanner.decision(
            local: local, incoming: HealthRestoreVersion(updatedAt: now)), .keepLocal)
        XCTAssertEqual(HealthRestorePlanner.decision(
            local: local,
            incoming: HealthRestoreVersion(updatedAt: now.addingTimeInterval(-1))), .keepLocal)
    }

    func testRestorePlannerAppliesNewerRowsAndTombstones() {
        let now = Date()
        XCTAssertEqual(HealthRestorePlanner.decision(
            local: nil, incoming: HealthRestoreVersion(updatedAt: now)), .insert)
        XCTAssertEqual(HealthRestorePlanner.decision(
            local: HealthRestoreVersion(updatedAt: now),
            incoming: HealthRestoreVersion(updatedAt: now.addingTimeInterval(1))), .replaceLocal)
        XCTAssertEqual(HealthRestorePlanner.decision(
            local: HealthRestoreVersion(updatedAt: now),
            incoming: HealthRestoreVersion(updatedAt: now.addingTimeInterval(1),
                                           deletedAt: now.addingTimeInterval(1))), .applyTombstone)
    }
}
