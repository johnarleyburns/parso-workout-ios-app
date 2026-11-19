import Foundation
import Testing
@testable import CadenceCore

struct HealthBackupContractsTests {
    @Test func ownerSetMetadataIsTypedAndExcludesPartnerIdentity() {
        let exercise = Exercise(name: "Cable Row")
        let set = SetEntry(weight: 57, reps: 8, rpe: 8, note: "smooth", exercise: exercise)
        let reference = CrossStoreReferenceResolver().exercise(for: set, exercises: [exercise])
        let metadata = CladironHealthBackup.ownerSetMetadata(for: set, exercise: reference)

        #expect(CladironHealthBackup.isSupported(metadata))
        #expect(metadata[CladironHealthBackup.syncIdentifierKey] == set.id.uuidString)
        #expect(metadata[CladironHealthBackup.exerciseNameKey] == "Cable Row")
        #expect(metadata[CladironHealthBackup.weightKgKey] == "57.0")
        #expect(metadata[CladironHealthBackup.repsKey] == "8")
        #expect(metadata[CladironHealthBackup.performerKey] == nil)
    }

    @Test func syncVersionIsMonotonicInMilliseconds() {
        let first = Date(timeIntervalSince1970: 10)
        let second = Date(timeIntervalSince1970: 10.001)
        #expect(CladironHealthBackup.syncVersion(for: first) <
                          CladironHealthBackup.syncVersion(for: second))
    }

    @Test func restorePlannerKeepsEqualOrOlderLocalData() {
        let now = Date()
        let local = HealthRestoreVersion(updatedAt: now)
        #expect(HealthRestorePlanner.decision(
            local: local, incoming: HealthRestoreVersion(updatedAt: now)) == .keepLocal)
        #expect(HealthRestorePlanner.decision(
            local: local,
            incoming: HealthRestoreVersion(updatedAt: now.addingTimeInterval(-1))) == .keepLocal)
    }

    @Test func restorePlannerAppliesNewerRowsAndTombstones() {
        let now = Date()
        #expect(HealthRestorePlanner.decision(
            local: nil, incoming: HealthRestoreVersion(updatedAt: now)) == .insert)
        #expect(HealthRestorePlanner.decision(
            local: HealthRestoreVersion(updatedAt: now),
            incoming: HealthRestoreVersion(updatedAt: now.addingTimeInterval(1))) == .replaceLocal)
        #expect(HealthRestorePlanner.decision(
            local: HealthRestoreVersion(updatedAt: now),
            incoming: HealthRestoreVersion(updatedAt: now.addingTimeInterval(1),
                                           deletedAt: now.addingTimeInterval(1))) == .applyTombstone)
    }
}
