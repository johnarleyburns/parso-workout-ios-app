import Foundation
import Testing
@testable import CadenceCore

struct HealthRestoreContractsTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func decoderRestoresOwnerOnlyStrengthPayloadWithSyncVersion() throws {
        let id = UUID()
        let set = CladironHealthBackup.SetPayload(
            id: UUID(), exerciseKey: "bench-press", exerciseName: "Bench Press",
            weightKg: 57, reps: 8, rpe: 8, isWarmup: false,
            usesBodyweight: false, note: "last rep was hard", order: 0,
            completedAt: start.addingTimeInterval(120))
        let setData = try JSONEncoder().encode([set])
        var metadata = CladironHealthBackup.baseMetadata(
            id: id, updatedAt: start.addingTimeInterval(300))
        metadata[CladironHealthBackup.ownerSetsKey] = String(decoding: setData, as: UTF8.self)
        metadata[CladironHealthBackup.titleKey] = "Upper body"

        let object = try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
            healthObjectID: UUID(), kind: .strength, activityType: .traditionalStrength,
            start: start, end: start.addingTimeInterval(600), activeEnergyKcal: 42,
            heartRate: [HRSamplePoint(t: 30, bpm: 120)], metadata: metadata,
            source: .iphone))

        guard case .strength(let summary, _, _) = object else {
            Issue.record("expected a strength restore object")
            return
        }
        #expect(summary.id == id)
        #expect(summary.titleMetadata == "Upper body")
        #expect(summary.metadata[CladironHealthBackup.ownerSetsKey] == metadata[CladironHealthBackup.ownerSetsKey])
        #expect(summary.updatedAt == start.addingTimeInterval(300))
    }

    @Test func decoderCreatesSummaryOnlyObjectForLegacyHealthWorkout() throws {
        let healthID = UUID()
        let object = try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
            healthObjectID: healthID, kind: .strength, activityType: .traditionalStrength,
            start: start, end: start.addingTimeInterval(900), activeEnergyKcal: 80,
            metadata: [:], source: .watch))

        guard case .legacySummary(let summary) = object else {
            Issue.record("expected a legacy summary")
            return
        }
        #expect(summary.healthObjectID == healthID)
        #expect(summary.source == .watch)
        #expect(HealthBackupRestorePlanner.plan(incoming: [object], local: []).summariesOnly == 1)
    }

    @Test func decoderRejectsNewerSchemaAndMalformedOwnerSets() throws {
        let id = UUID()
        var newer = CladironHealthBackup.baseMetadata(id: id, updatedAt: start)
        newer[CladironHealthBackup.schemaKey] = "99"
        #expect(throws: HealthBackupDecodeError.unknownSchema(99)) {
            try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
                healthObjectID: UUID(), kind: .cardio, activityType: .running,
                start: start, end: start.addingTimeInterval(60), metadata: newer, source: .iphone))
        }

        var malformed = CladironHealthBackup.baseMetadata(id: id, updatedAt: start)
        malformed[CladironHealthBackup.ownerSetsKey] = "not-json"
        #expect(throws: HealthBackupDecodeError.invalidOwnerSets) {
            try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
                healthObjectID: UUID(), kind: .strength, activityType: .traditionalStrength,
                start: start, end: start.addingTimeInterval(60), metadata: malformed, source: .iphone))
        }
    }

    @Test func decoderRestoresAllAssessmentInputs() throws {
        let id = UUID()
        var metadata = CladironHealthBackup.baseMetadata(id: id, updatedAt: start.addingTimeInterval(45))
        metadata[CladironHealthBackup.assessmentKindKey] = AssessmentKind.e1RM.rawValue
        metadata[CladironHealthBackup.assessmentValueKey] = "95.5"
        metadata[CladironHealthBackup.assessmentInputWeightKey] = "85.5"
        metadata[CladironHealthBackup.assessmentInputRepsKey] = "5"
        metadata[CladironHealthBackup.assessmentExerciseNameKey] = "Bench Press"
        metadata[CladironHealthBackup.assessmentProtocolKey] = "Five-rep estimate"
        metadata[CladironHealthBackup.assessmentNotesKey] = "After warm-up"
        metadata[CladironHealthBackup.assessmentInputAgeKey] = "39"
        metadata[CladironHealthBackup.assessmentInputSexKey] = "1"

        let object = try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
            healthObjectID: UUID(), kind: .strength, activityType: .traditionalStrength,
            start: start, end: start.addingTimeInterval(60), metadata: metadata, source: .iphone))

        guard case .assessment(let payload, _, _) = object else {
            Issue.record("expected an assessment restore object")
            return
        }
        #expect(payload.inputWeight == 85.5)
        #expect(payload.inputReps == 5)
        #expect(payload.exerciseName == "Bench Press")
        #expect(payload.protocolName == "Five-rep estimate")
        #expect(payload.notes == "After warm-up")
        #expect(payload.inputAge == 39)
        #expect(payload.inputSex == 1)
    }

    @Test func restorePlannerDeduplicatesSourcesAndNewerHealthReplacesOlderLocal() throws {
        let id = UUID()
        var olderMetadata = CladironHealthBackup.baseMetadata(id: id, updatedAt: start.addingTimeInterval(100))
        olderMetadata[CladironHealthBackup.titleKey] = "Older copy"
        let newerMetadata = CladironHealthBackup.baseMetadata(id: id, updatedAt: start.addingTimeInterval(200))
        let oldObject = try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
            healthObjectID: UUID(), kind: .cardio, activityType: .running, start: start,
            end: start.addingTimeInterval(60), metadata: olderMetadata, source: .watch))
        let newObject = try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
            healthObjectID: UUID(), kind: .cardio, activityType: .running, start: start,
            end: start.addingTimeInterval(60), metadata: newerMetadata, source: .iphone))
        let local = HealthRestoreLocalState(kind: .cardioWorkout, id: id,
                                            updatedAt: start.addingTimeInterval(150))

        let plan = HealthBackupRestorePlanner.plan(incoming: [oldObject, newObject], local: [local])
        #expect(plan.operations.count == 1)
        #expect(plan.operations.first?.action == .replace)
        #expect(plan.replacements == 1)
    }

    @Test func restorePlannerKeepsNewerLocalAndMatchesLegacyByHealthObjectID() throws {
        let id = UUID()
        let metadata = CladironHealthBackup.baseMetadata(id: id, updatedAt: start)
        let object = try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
            healthObjectID: UUID(), kind: .cardio, activityType: .running, start: start,
            end: start.addingTimeInterval(60), metadata: metadata, source: .iphone))
        let local = HealthRestoreLocalState(kind: .cardioWorkout, id: id,
                                            updatedAt: start.addingTimeInterval(100))
        let plan = HealthBackupRestorePlanner.plan(incoming: [object], local: [local])
        #expect(plan.skipped == 1)

        let legacyID = UUID()
        let legacy = try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
            healthObjectID: legacyID, kind: .strength, activityType: .traditionalStrength,
            start: start, end: start.addingTimeInterval(60), metadata: [:], source: .iphone))
        let matching = HealthRestoreLocalState(kind: .strengthSession, id: UUID(),
                                               updatedAt: start.addingTimeInterval(-100),
                                               healthObjectID: legacyID)
        #expect(HealthBackupRestorePlanner.plan(incoming: [legacy], local: [matching]).skipped == 1)
    }

    @Test func restorePlannerTurnsHealthDeletionIntoLocalDelete() {
        let healthID = UUID()
        let local = HealthRestoreLocalState(kind: .cardioWorkout, id: UUID(),
                                            updatedAt: start,
                                            healthObjectID: healthID)
        let plan = HealthBackupRestorePlanner.plan(
            incoming: [.deleted(healthObjectID: healthID)], local: [local])
        #expect(plan.operations.count == 1)
        #expect(plan.operations.first?.action == .delete)
    }

    @Test func unknownHealthDeletionIsIgnored() {
        let plan = HealthBackupRestorePlanner.plan(
            incoming: [.deleted(healthObjectID: UUID())], local: [])
        #expect(plan.skipped == 1)
    }
}

private extension StrengthWorkoutSummary {
    var titleMetadata: String? { metadata[CladironHealthBackup.titleKey] }
}
