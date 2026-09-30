import XCTest
@testable import CadenceCore

final class HealthRestoreContractsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testDecoderRestoresOwnerOnlyStrengthPayloadWithSyncVersion() throws {
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
            return XCTFail("expected a strength restore object")
        }
        XCTAssertEqual(summary.id, id)
        XCTAssertEqual(summary.titleMetadata, "Upper body")
        XCTAssertEqual(summary.metadata[CladironHealthBackup.ownerSetsKey], metadata[CladironHealthBackup.ownerSetsKey])
        XCTAssertEqual(summary.updatedAt, start.addingTimeInterval(300))
    }

    func testDecoderCreatesSummaryOnlyObjectForLegacyHealthWorkout() throws {
        let healthID = UUID()
        let object = try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
            healthObjectID: healthID, kind: .strength, activityType: .traditionalStrength,
            start: start, end: start.addingTimeInterval(900), activeEnergyKcal: 80,
            metadata: [:], source: .watch))

        guard case .legacySummary(let summary) = object else {
            return XCTFail("expected a legacy summary")
        }
        XCTAssertEqual(summary.healthObjectID, healthID)
        XCTAssertEqual(summary.source, .watch)
        XCTAssertEqual(HealthBackupRestorePlanner.plan(incoming: [object], local: []).summariesOnly, 1)
    }

    func testDecoderRejectsNewerSchemaAndMalformedOwnerSets() throws {
        let id = UUID()
        var newer = CladironHealthBackup.baseMetadata(id: id, updatedAt: start)
        newer[CladironHealthBackup.schemaKey] = "99"
        XCTAssertThrowsError(try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
            healthObjectID: UUID(), kind: .cardio, activityType: .running,
            start: start, end: start.addingTimeInterval(60), metadata: newer, source: .iphone))) { error in
            XCTAssertEqual(error as? HealthBackupDecodeError, .unknownSchema(99))
        }

        var malformed = CladironHealthBackup.baseMetadata(id: id, updatedAt: start)
        malformed[CladironHealthBackup.ownerSetsKey] = "not-json"
        XCTAssertThrowsError(try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
            healthObjectID: UUID(), kind: .strength, activityType: .traditionalStrength,
            start: start, end: start.addingTimeInterval(60), metadata: malformed, source: .iphone))) { error in
            XCTAssertEqual(error as? HealthBackupDecodeError, .invalidOwnerSets)
        }
    }

    func testDecoderRestoresAllAssessmentInputs() throws {
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
            return XCTFail("expected an assessment restore object")
        }
        XCTAssertEqual(payload.inputWeight, 85.5)
        XCTAssertEqual(payload.inputReps, 5)
        XCTAssertEqual(payload.exerciseName, "Bench Press")
        XCTAssertEqual(payload.protocolName, "Five-rep estimate")
        XCTAssertEqual(payload.notes, "After warm-up")
        XCTAssertEqual(payload.inputAge, 39)
        XCTAssertEqual(payload.inputSex, 1)
    }

    func testRestorePlannerDeduplicatesSourcesAndNewerHealthReplacesOlderLocal() throws {
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
        XCTAssertEqual(plan.operations.count, 1)
        XCTAssertEqual(plan.operations.first?.action, .replace)
        XCTAssertEqual(plan.replacements, 1)
    }

    func testRestorePlannerKeepsNewerLocalAndMatchesLegacyByHealthObjectID() throws {
        let id = UUID()
        let metadata = CladironHealthBackup.baseMetadata(id: id, updatedAt: start)
        let object = try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
            healthObjectID: UUID(), kind: .cardio, activityType: .running, start: start,
            end: start.addingTimeInterval(60), metadata: metadata, source: .iphone))
        let local = HealthRestoreLocalState(kind: .cardioWorkout, id: id,
                                            updatedAt: start.addingTimeInterval(100))
        let plan = HealthBackupRestorePlanner.plan(incoming: [object], local: [local])
        XCTAssertEqual(plan.skipped, 1)

        let legacyID = UUID()
        let legacy = try HealthBackupDecoder.workout(HealthWorkoutReadPayload(
            healthObjectID: legacyID, kind: .strength, activityType: .traditionalStrength,
            start: start, end: start.addingTimeInterval(60), metadata: [:], source: .iphone))
        let matching = HealthRestoreLocalState(kind: .strengthSession, id: UUID(),
                                               updatedAt: start.addingTimeInterval(-100),
                                               healthObjectID: legacyID)
        XCTAssertEqual(HealthBackupRestorePlanner.plan(incoming: [legacy], local: [matching]).skipped, 1)
    }
}

private extension StrengthWorkoutSummary {
    var titleMetadata: String? { metadata[CladironHealthBackup.titleKey] }
}
