import Foundation
import Testing
@testable import CadenceCore

struct RuntimePrescriptionAdapterTests {
    @Test func materializePreservesSetKindAndSupersetGroup() throws {
        let plan = PlanSessionSnapshot(id: UUID(), title: "Superset", items: [
            .strength(.init(id: UUID(), exerciseKey: "bench", exerciseName: "Bench Press",
                            supersetGroup: "A",
                            sets: [.init(id: UUID(), targetReps: 8, kind: .failure)]))
        ])
        let draft = try RuntimePrescriptionAdapter().materialize(planSession: plan, athlete: .init())
        #expect(draft.plannedPrescriptions.first?.supersetGroup == "A")
        #expect(draft.plannedPrescriptions.first?.sets.first?.kind == .failure)
    }

    @Test func materializeResolvesPercentAndPreservesIntentAndSourceIDs() throws {
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

        #expect(draft.plannedExerciseNames == ["Bench Press"])
        #expect(draft.plannedRepLadder == [5, 8])
        #expect(draft.plannedPrescriptions.first?.sourceItemID == itemID)
        #expect(draft.plannedPrescriptions.first?.exerciseKey == "bench_press")
        #expect(draft.plannedPrescriptions.first?.sets.first?.sourceSetID == setID)
        #expect(draft.plannedPrescriptions.first?.sets.first?.targetWeightKg == 70.5)
        #expect(draft.plannedPrescriptions.first?.sets.first?.oneRepMaxPercent == 0.70)
        #expect(draft.plannedPrescriptions.first?.sets.first?.targetRPE == 8)
        #expect(draft.plannedPrescriptions.first?.sets.first?.restSeconds == 150)
        #expect(draft.plannedPrescriptions.first?.sets.last?.isWarmup == true)
    }

    @Test func materializeIsResumableWhenExistingSessionIDIsSupplied() throws {
        let plan = PlanSessionSnapshot(id: UUID(), title: "Lower", items: [
            .strength(.init(id: UUID(), exerciseKey: "squat", exerciseName: "Back Squat",
                            sets: [.init(id: UUID(), targetReps: 5, load: .absoluteKg(100))]))
        ])
        let existingID = UUID()

        let first = try RuntimePrescriptionAdapter().materialize(
            planSession: plan, athlete: .init(), existingSessionID: existingID)
        let resumed = try RuntimePrescriptionAdapter().materialize(
            planSession: plan, athlete: .init(), existingSessionID: existingID)

        #expect(first.sessionID == existingID)
        #expect(resumed.sessionID == existingID)
        #expect(first.plannedPrescriptions == resumed.plannedPrescriptions)
    }

    @Test func legacyPlanFieldsArePopulatedAlongsideRichPrescriptions() throws {
        let plan = PlanSessionSnapshot(id: UUID(), title: "Push", items: [
            .strength(.init(id: UUID(), exerciseKey: "bench_press", exerciseName: "Bench Press",
                            sets: [.init(id: UUID(), targetReps: 8, load: .absoluteKg(60))])),
            .strength(.init(id: UUID(), exerciseKey: "row", exerciseName: "Row",
                            sets: [.init(id: UUID(), targetReps: 10, load: .absoluteKg(50))]))
        ])

        let draft = try RuntimePrescriptionAdapter().materialize(
            planSession: plan, athlete: .init())

        #expect(draft.plannedRepLadder == [8])
        #expect(draft.prescribedLoadKg == 60)
        #expect(draft.plannedPrescriptions.count == 2)
    }

    @Test func applyingDraftKeepsPlanSourceAndCreatesNoResults() throws {
        let planSessionID = UUID()
        let plan = PlanSessionSnapshot(id: planSessionID, title: "Push", items: [
            .strength(.init(id: UUID(), exerciseKey: "bench_press", exerciseName: "Bench Press",
                            sets: [.init(id: UUID(), targetReps: 5, load: .absoluteKg(80))]))
        ])
        let draft = try RuntimePrescriptionAdapter().materialize(
            planSession: plan, athlete: .init())
        let session = WorkoutSession()

        draft.apply(to: session)

        #expect(session.planSessionID == planSessionID)
        #expect(session.plannedExerciseNames == ["Bench Press"])
        #expect(session.plannedPrescriptions.first?.sets.first?.targetWeightKg == 80)
        #expect(session.orderedSets.isEmpty,
                      "The adapter writes prescription metadata only")
    }

    @Test func stableCatalogKeyOutranksStaleDisplayNameProjection() throws {
        let template = try #require(ExerciseLibrary.starter.first { $0.name == "Bench Press" })
        let key = try #require(template.sourceExerciseID)
        let item = StrengthItem(
            exerciseKey: ExerciseKey(raw: key), order: 0,
            sets: [PrescribedSet(setIndex: 0, repTarget: .exact(8))])
        let session = Session(title: "Current plan", items: [.strength(item)])

        let draft = try RuntimePrescriptionAdapter().materialize(
            planSession: session,
            exerciseNameByKey: [key: "Old Bench Alias"],
            athlete: AthleteExecutionSnapshot())

        #expect(draft.plannedExerciseNames == ["Bench Press"])
        #expect(draft.plannedPrescriptions.first?.exerciseName == "Bench Press")
    }

    @Test func percentLoadRequiresAnExerciseSpecificOneRepMax() {
        let plan = PlanSessionSnapshot(id: UUID(), title: "Push", items: [
            .strength(.init(id: UUID(), exerciseKey: "bench_press", exerciseName: "Bench Press",
                            sets: [.init(id: UUID(), targetReps: 5, load: .oneRepMaxPercent(0.70))]))
        ])

        #expect(throws: RuntimePrescriptionAdapterError.missingOneRepMax(exerciseKey: "bench_press")) {
            try RuntimePrescriptionAdapter().materialize(planSession: plan, athlete: .init())
        }
    }

    @Test func legacyPrescriptionJSONDefaultsMissingWarmupFlag() throws {
        let legacyJSON = Data(#"{"targetReps":5,"targetWeightKg":100}"#.utf8)

        let prescription = try JSONDecoder().decode(PlannedSetPrescription.self, from: legacyJSON)

        #expect(prescription.targetReps == 5)
        #expect(prescription.targetWeightKg == 100)
        #expect(!prescription.isWarmup)
    }

    @Test func watchPlanPayloadMaterializesStrengthAndCardio() throws {
        let sessionID = UUID()
        let session = PlanSessionSnapshot(
            id: sessionID,
            title: "Upper + run",
            items: [
                .strength(.init(
                    id: UUID(), exerciseKey: "bench_press", exerciseName: "Bench Press",
                    sets: [.init(id: UUID(), targetReps: 5, load: .absoluteKg(80))])),
                .cardio(.init(
                    id: UUID(), title: "Easy run", kind: "run", durationSeconds: 1_800,
                    distanceMeters: 5_000, targetZone: 2))
            ])

        let payload = try WatchPlanPayload.make(from: session, athlete: .init())

        #expect(payload.version == WatchPlanPayload.currentVersion)
        #expect(payload.planSessionID == sessionID)
        #expect(payload.strength?.prescriptions.first?.sets.first?.targetWeightKg == 80)
        #expect(payload.cardio.first?.kind == "run")
        #expect(payload.cardio.first?.durationSeconds == 1_800)
        #expect(payload.cardio.first?.distanceMeters == 5_000)
        #expect(payload.cardio.first?.targetZone == 2)
    }

    @Test func unifiedCardioPlanPreservesDistanceAndHeartRateZoneInWatchPayload() throws {
        let cardio = CardioItem(
            id: UUID(), order: 0,
            prescription: .steadyState(SteadyState(
                activity: .run, durationSeconds: 1_800, distanceMeters: 5_000,
                intensity: .heartRateZone(2))))
        let unified = Session(
            id: UUID(), title: "Run plan",
            items: [.cardio(cardio)])

        let payload = try WatchPlanPayload.make(
            from: PlanSessionSnapshot(session: unified), athlete: .init())

        #expect(payload.cardio.count == 1)
        #expect(payload.cardio.first?.distanceMeters == 5_000)
        #expect(payload.cardio.first?.targetZone == 2)
    }

    @Test func unifiedSessionConversionPreservesAllItemFamiliesAndStableIDs() throws {
        let strengthItemID = UUID()
        let setID = UUID()
        let cardioID = UUID()
        let mobilityID = UUID()
        let instructionID = UUID()
        let unified = Session(
            id: UUID(), title: "Full session",
            items: [
                .instruction(InstructionItem(id: instructionID, order: 0, text: "Brace first")),
                .strength(StrengthItem(
                    id: strengthItemID, exerciseKey: ExerciseKey(raw: "incline_crunch"), order: 1,
                    sets: [PrescribedSet(id: setID, setIndex: 0, repTarget: .exact(12),
                                         load: .bodyweight, restSeconds: 60)])),
                .cardio(CardioItem(
                    id: cardioID, order: 2,
                    prescription: .steadyState(SteadyState(activity: .run, durationSeconds: 600)))),
                .mobility(MobilityItem(
                    id: mobilityID, order: 3, name: "Couch stretch", rounds: 2,
                    perRound: .duration(seconds: 30)))
            ])

        let snapshot = PlanSessionSnapshot(
            session: unified,
            exerciseNameByKey: ["incline_crunch": "Incline Crunch"])

        #expect(snapshot.items.count == 4)
        #expect(snapshot.strengthItems.first?.id == strengthItemID)
        #expect(snapshot.strengthItems.first?.exerciseName == "Incline Crunch")
        #expect(snapshot.strengthItems.first?.sets.first?.id == setID)
        #expect(snapshot.strengthItems.first?.sets.first?.load == .bodyweight)
        #expect(snapshot.items.contains {
            if case let .cardio(item) = $0 {
                return item.id == cardioID && item.kind == "run" && item.durationSeconds == 600
            }
            return false
        })
        #expect(snapshot.items.contains {
            if case let .mobility(item) = $0 {
                return item.id == mobilityID && item.rounds == 2
            }
            return false
        })
        #expect(snapshot.items.contains {
            if case let .instruction(item) = $0 {
                return item.id == instructionID && item.text == "Brace first"
            }
            return false
        })
    }

    @Test func unifiedSessionMaterializerResolvesPercentLoadThroughSessionOverload() throws {
        let itemID = UUID()
        let setID = UUID()
        let unified = Session(
            id: UUID(), title: "Press day",
            items: [.strength(StrengthItem(
                id: itemID, exerciseKey: ExerciseKey(raw: "bench_press"), order: 0,
                sets: [PrescribedSet(id: setID, setIndex: 0, repTarget: .exact(5),
                                     load: .percent1RM(percent: 0.75, calculatedWeight: nil))]))])

        let draft = try RuntimePrescriptionAdapter().materialize(
            planSession: unified,
            exerciseNameByKey: ["bench_press": "Bench Press"],
            athlete: AthleteExecutionSnapshot(
                oneRepMaxKgByExerciseKey: ["bench_press": 100], loadIncrementKg: 2.5))

        #expect(draft.planSessionID == unified.id)
        #expect(draft.plannedExerciseNames == ["Bench Press"])
        #expect(draft.plannedPrescriptions.first?.sourceItemID == itemID)
        #expect(draft.plannedPrescriptions.first?.sets.first?.sourceSetID == setID)
        #expect(draft.plannedPrescriptions.first?.sets.first?.targetWeightKg == 75)
        #expect(draft.plannedPrescriptions.first?.sets.first?.oneRepMaxPercent == 0.75)
    }
}
