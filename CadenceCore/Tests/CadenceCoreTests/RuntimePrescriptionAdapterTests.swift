import XCTest
@testable import CadenceCore

final class RuntimePrescriptionAdapterTests: XCTestCase {
    func testMaterializeResolvesPercentAndPreservesIntentAndSourceIDs() throws {
        let itemID = UUID()
        let setID = UUID()
        let session = PlanSessionSnapshot(
            id: UUID(), title: "Upper",
            items: [.strength(.init(
                id: itemID, exerciseKey: "bench_press", exerciseName: "Bench Press",
                sets: [
                    .init(id: setID, targetReps: 5,
                          load: .oneRepMaxPercent(0.70), targetRPE: 8, restSeconds: 150),
                    .init(id: UUID(), targetReps: 8,
                          load: .absoluteKg(60), isWarmup: true)
                ]))])

        let draft = try RuntimePrescriptionAdapter().materialize(
            planSession: session,
            athlete: .init(oneRepMaxKgByExerciseKey: ["bench_press": 101], loadIncrementKg: 0.5),
            existingSessionID: UUID())

        XCTAssertEqual(draft.plannedExerciseNames, ["Bench Press"])
        XCTAssertEqual(draft.plannedRepLadder, [5, 8])
        XCTAssertEqual(draft.plannedPrescriptions.first?.sourceItemID, itemID)
        XCTAssertEqual(draft.plannedPrescriptions.first?.exerciseKey, "bench_press")
        XCTAssertEqual(draft.plannedPrescriptions.first?.sets.first?.sourceSetID, setID)
        XCTAssertEqual(draft.plannedPrescriptions.first?.sets.first?.targetWeightKg, 70.5)
        XCTAssertEqual(draft.plannedPrescriptions.first?.sets.first?.oneRepMaxPercent, 0.70)
        XCTAssertEqual(draft.plannedPrescriptions.first?.sets.first?.targetRPE, 8)
        XCTAssertEqual(draft.plannedPrescriptions.first?.sets.first?.restSeconds, 150)
        XCTAssertEqual(draft.plannedPrescriptions.first?.sets.last?.isWarmup, true)
    }

    func testMaterializeIsResumableWhenExistingSessionIDIsSupplied() throws {
        let plan = PlanSessionSnapshot(id: UUID(), title: "Lower", items: [
            .strength(.init(id: UUID(), exerciseKey: "squat", exerciseName: "Back Squat",
                            sets: [.init(id: UUID(), targetReps: 5, load: .absoluteKg(100))]))
        ])
        let existingID = UUID()

        let first = try RuntimePrescriptionAdapter().materialize(
            planSession: plan, athlete: .init(), existingSessionID: existingID)
        let resumed = try RuntimePrescriptionAdapter().materialize(
            planSession: plan, athlete: .init(), existingSessionID: existingID)

        XCTAssertEqual(first.sessionID, existingID)
        XCTAssertEqual(resumed.sessionID, existingID)
        XCTAssertEqual(first.plannedPrescriptions, resumed.plannedPrescriptions)
    }

    func testLegacyPlanFieldsArePopulatedAlongsideRichPrescriptions() throws {
        let plan = PlanSessionSnapshot(id: UUID(), title: "Push", items: [
            .strength(.init(id: UUID(), exerciseKey: "bench_press", exerciseName: "Bench Press",
                            sets: [.init(id: UUID(), targetReps: 8, load: .absoluteKg(60))])),
            .strength(.init(id: UUID(), exerciseKey: "row", exerciseName: "Row",
                            sets: [.init(id: UUID(), targetReps: 10, load: .absoluteKg(50))]))
        ])

        let draft = try RuntimePrescriptionAdapter().materialize(
            planSession: plan, athlete: .init())

        XCTAssertEqual(draft.plannedRepLadder, [8])
        XCTAssertEqual(draft.prescribedLoadKg, 60)
        XCTAssertEqual(draft.plannedPrescriptions.count, 2)
    }

    func testApplyingDraftKeepsPlanSourceAndCreatesNoResults() throws {
        let planSessionID = UUID()
        let plan = PlanSessionSnapshot(id: planSessionID, title: "Push", items: [
            .strength(.init(id: UUID(), exerciseKey: "bench_press", exerciseName: "Bench Press",
                            sets: [.init(id: UUID(), targetReps: 5, load: .absoluteKg(80))]))
        ])
        let draft = try RuntimePrescriptionAdapter().materialize(
            planSession: plan, athlete: .init())
        let session = WorkoutSession()

        draft.apply(to: session)

        XCTAssertEqual(session.planSessionID, planSessionID)
        XCTAssertEqual(session.plannedExerciseNames, ["Bench Press"])
        XCTAssertEqual(session.plannedPrescriptions.first?.sets.first?.targetWeightKg, 80)
        XCTAssertTrue(session.orderedSets.isEmpty,
                      "The adapter writes prescription metadata only")
    }

    func testPercentLoadRequiresAnExerciseSpecificOneRepMax() {
        let plan = PlanSessionSnapshot(id: UUID(), title: "Push", items: [
            .strength(.init(id: UUID(), exerciseKey: "bench_press", exerciseName: "Bench Press",
                            sets: [.init(id: UUID(), targetReps: 5, load: .oneRepMaxPercent(0.70))]))
        ])

        XCTAssertThrowsError(try RuntimePrescriptionAdapter().materialize(
            planSession: plan, athlete: .init())) { error in
            XCTAssertEqual(error as? RuntimePrescriptionAdapterError,
                           .missingOneRepMax(exerciseKey: "bench_press"))
        }
    }

    func testLegacyPrescriptionJSONDefaultsMissingWarmupFlag() throws {
        let legacyJSON = Data(#"{"targetReps":5,"targetWeightKg":100}"#.utf8)

        let prescription = try JSONDecoder().decode(PlannedSetPrescription.self, from: legacyJSON)

        XCTAssertEqual(prescription.targetReps, 5)
        XCTAssertEqual(prescription.targetWeightKg, 100)
        XCTAssertFalse(prescription.isWarmup)
    }

    func testWatchPlanPayloadMaterializesStrengthAndCardio() throws {
        let sessionID = UUID()
        let session = PlanSessionSnapshot(
            id: sessionID,
            title: "Upper + run",
            items: [
                .strength(.init(
                    id: UUID(), exerciseKey: "bench_press", exerciseName: "Bench Press",
                    sets: [.init(id: UUID(), targetReps: 5, load: .absoluteKg(80))])),
                .cardio(.init(
                    id: UUID(), title: "Easy run", kind: "run", durationSeconds: 1_800))
            ])

        let payload = try WatchPlanPayload.make(from: session, athlete: .init())

        XCTAssertEqual(payload.version, WatchPlanPayload.currentVersion)
        XCTAssertEqual(payload.planSessionID, sessionID)
        XCTAssertEqual(payload.strength?.prescriptions.first?.sets.first?.targetWeightKg, 80)
        XCTAssertEqual(payload.cardio.first?.kind, "run")
        XCTAssertEqual(payload.cardio.first?.durationSeconds, 1_800)
    }
}
