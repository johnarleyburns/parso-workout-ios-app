import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

@MainActor
final class EditablePlanTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    func testFromSessionCopiesOwnerSets() throws {
        let ctx = try makeContext()
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        let s = WorkoutSession(title: "Push Day", date: Date()); ctx.insert(s)
        ctx.insert(SetEntry(weight: 100, reps: 5, order: 0, completedAt: s.date, session: s, exercise: bench))
        ctx.insert(SetEntry(weight: 100, reps: 4, order: 1, completedAt: s.date, session: s, exercise: bench))
        try ctx.save()

        let plan = EditablePlan.from(session: s)
        XCTAssertEqual(plan.title, "Push Day")
        XCTAssertEqual(plan.exercises.count, 1)
        XCTAssertEqual(plan.exercises.first?.sets.count, 2)
        XCTAssertEqual(plan.exercises.first?.sets.map(\.targetReps), [5, 4])
    }

    func testFromPlanSeedsSetsFromLadder() {
        let item = PlanItem(id: 1, movement: "Back Squat", reps: 5, targetSets: nil)
        let wp = WorkoutPlan(id: "preset", name: "5x5", source: .strengthPreset,
                             scheme: .strength, items: [item])
        let plan = EditablePlan.from(plan: wp, ladder: [5, 5, 5], unit: .kilograms)
        XCTAssertEqual(plan.title, "5x5")
        XCTAssertEqual(plan.exercises.count, 1)
        XCTAssertEqual(plan.exercises.first?.sets.count, 3)
        XCTAssertEqual(plan.exercises.first?.sets.map(\.targetReps), [5, 5, 5])
    }

    func testFromPlanWithoutLadderDefaultsToThreeSets() {
        let item = PlanItem(id: 1, movement: "Back Squat", reps: 8, targetSets: nil)
        let wp = WorkoutPlan(id: "p", name: "P", source: .strengthPreset, scheme: .strength, items: [item])
        let plan = EditablePlan.from(plan: wp, ladder: nil, unit: .kilograms)
        XCTAssertEqual(plan.exercises.first?.sets.count, 3)
        XCTAssertEqual(plan.exercises.first?.sets.map(\.targetReps), [8, 8, 8])
    }

    /// Field test 2026-08-18 #2: a resolved coach load must survive into the
    /// editable plan, and a bodyweight movement must stay unweighted (D4).
    func testCoachPlanCarriesResolvedWeightsIntoEditableSets() {
        let session = CoachSession(
            id: "c2", kind: .strength, title: "Pull",
            exercises: [CoachSession.RecommendedExercise(
                name: "Standing Dumbbell Upright Row",
                sets: 3, repsLow: 12, loadKg: 22.5, rir: 2)])
        let plan = EditablePlan.from(coach: session)
        let sets = plan?.exercises.first?.sets ?? []
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets.allSatisfy { $0.targetWeight == 22.5 }, true,
                       "a resolved load must reach every planned set, not render as BW")
    }

    func testCoachPlanBodyweightExerciseHasNilTargetWeight() {
        let session = CoachSession(
            id: "c3", kind: .strength, title: "Push",
            exercises: [CoachSession.RecommendedExercise(name: "Push-Up", sets: 3, repsLow: 20, rir: 2)])
        let plan = EditablePlan.from(coach: session)
        XCTAssertEqual(plan?.exercises.first?.sets.allSatisfy { $0.targetWeight == nil }, true)
        XCTAssertTrue(ExerciseLoading.isBodyweight(named: "Push-Up"),
                      "which is why the editor is allowed to print BW for it")
    }

    func testFromCoachSessionMapsExercises() {
        let ex = CoachSession.RecommendedExercise(name: "Bench Press", sets: 3, repsLow: 8, loadKg: 60, rir: 2)
        let session = CoachSession(id: "c1", kind: .strength, title: "Upper", exercises: [ex])
        let plan = EditablePlan.from(coach: session)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.title, "Upper")
        XCTAssertEqual(plan?.warmupMinutes, 5)
        XCTAssertEqual(plan?.exercises.first?.sets.count, 3)
        XCTAssertEqual(plan?.exercises.first?.sets.allSatisfy { $0.targetReps == 8 }, true)
        XCTAssertEqual(plan?.exercises.first?.sets.allSatisfy { $0.targetWeight == 60 }, true)
        XCTAssertEqual(plan?.exercises.first?.notes, "Target ≤2 RIR")
    }

    func testFromCoachSessionNilWhenNoExercises() {
        let session = CoachSession(id: "c2", kind: .strength, title: "Empty", exercises: nil)
        XCTAssertNil(EditablePlan.from(coach: session))
    }

    func testApplyPreservesEachExerciseSetLadderAndWeight() {
        let plan = EditablePlan(
            title: "Mixed",
            warmupMinutes: 5,
            cooldownMinutes: 0,
            exercises: [
                EditableExercise(name: "Bench Press", sets: [
                    EditableSet(targetReps: 8, targetWeight: 60),
                    EditableSet(targetReps: 6, targetWeight: 62.5)
                ], notes: ""),
                EditableExercise(name: "Back Squat", sets: [
                    EditableSet(targetReps: 5, targetWeight: 100),
                    EditableSet(targetReps: 5, targetWeight: 100),
                    EditableSet(targetReps: 3, targetWeight: 105)
                ], notes: "")
            ])
        let session = WorkoutSession(title: plan.title)
        plan.apply(to: session)
        XCTAssertEqual(session.plannedPrescriptions, [
            PlannedExercisePrescription(exerciseName: "Bench Press", sets: [
                PlannedSetPrescription(targetReps: 8, targetWeightKg: 60),
                PlannedSetPrescription(targetReps: 6, targetWeightKg: 62.5)
            ]),
            PlannedExercisePrescription(exerciseName: "Back Squat", sets: [
                PlannedSetPrescription(targetReps: 5, targetWeightKg: 100),
                PlannedSetPrescription(targetReps: 5, targetWeightKg: 100),
                PlannedSetPrescription(targetReps: 3, targetWeightKg: 105)
            ])
        ])
    }

    func testApplyCarriesEngineProvenanceIntoSession() {
        let json = Data(#"{"planId":"generated-plan"}"#.utf8)
        let plan = EditablePlan(
            warmupMinutes: 0,
            cooldownMinutes: 0,
            exercises: [EditableExercise(
                name: "Bench Press",
                sets: [EditableSet(targetReps: 8, targetWeight: nil)],
                notes: "")],
            enginePlanId: "generated-plan",
            engineRevisionId: "r1",
            enginePlanJSON: json)
        let session = WorkoutSession(title: plan.title)

        plan.apply(to: session)

        XCTAssertEqual(session.enginePlanId, "generated-plan")
        XCTAssertEqual(session.engineRevisionId, "r1")
        XCTAssertEqual(session.enginePlanJSON, json)
    }

    func testNormalizedPartnerIDsDropsOwnerOnly() {
        let owner = UUID()
        XCTAssertEqual(EditablePlan.normalizedPartnerIDs([owner], ownerID: owner), [])
    }

    func testNormalizedPartnerIDsKeepsPartnersAndDedupes() {
        let owner = UUID(); let a = UUID(); let b = UUID()
        let result = EditablePlan.normalizedPartnerIDs([owner, a, a, b], ownerID: owner)
        XCTAssertEqual(result, [owner, a, b])
    }

    // Coach-user-control Phase 5 — "do a strength workout anyway" must always
    // produce a real, editable full-body plan, even with zero history.
    func testStrengthAnywayProducesEditablePlan() {
        let facts = CoachFacts.make(from: [], goal: .hypertrophy,
                                    experience: .intermediate, now: Date())
        let plan = EditablePlan.strengthAnyway(facts: facts)
        XCTAssertNotNil(plan, "Strength-anyway must offer a plan even with no history")
        XCTAssertFalse(plan?.exercises.isEmpty ?? true)
        XCTAssertEqual(plan?.title, "Strength session")
        XCTAssertTrue(plan?.exercises.allSatisfy { !$0.sets.isEmpty } ?? false,
                      "Every exercise carries a concrete set prescription")
    }

    func testStrengthAnywayUsesGoalRepScheme() {
        let facts = CoachFacts.make(from: [], goal: .strength,
                                    experience: .intermediate, now: Date())
        let plan = EditablePlan.strengthAnyway(facts: facts)
        let reps = plan?.exercises.first?.sets.map(\.targetReps) ?? []
        XCTAssertFalse(reps.isEmpty)
        XCTAssertTrue(reps.allSatisfy { TrainingGoal.strength.repRange.contains($0) },
                      "Rep targets should honor the strength goal's range, got \(reps)")
    }

    // MARK: - Per-performer plans (field test 2026-08-18 #4, decision D11)

    private func planWithPartner(_ partnerID: UUID) -> EditablePlan {
        let plan = EditablePlan(
            warmupMinutes: 0, cooldownMinutes: 0,
            exercises: [EditableExercise(name: "Bench Press",
                                         sets: [EditableSet(targetReps: 8, targetWeight: 100),
                                                EditableSet(targetReps: 6, targetWeight: 105)],
                                         notes: "")],
            partnerIDs: [partnerID])
        return PartnerPlanResolver.fill(
            plan: plan,
            roster: [.init(performerID: nil, name: "Me"), .init(performerID: partnerID, name: "Alex")],
            history: { _, _ in .init(lastSets: [.init(weightKg: 60, reps: 12)], firstWorkingWeightKg: 60) })
    }

    func testApplyWritesPerformerPrescriptionsForEveryRosterMember() throws {
        let ctx = try makeContext()
        let partnerID = UUID()
        let session = WorkoutSession(title: "Push", date: Date()); ctx.insert(session)

        planWithPartner(partnerID).apply(to: session)

        let stored = session.plannedPerformerPrescriptions
        XCTAssertEqual(stored.count, 2)
        XCTAssertNil(stored[0].performerID, "The owner is stored first, keyed by nil")
        XCTAssertEqual(stored[1].performerID, partnerID.uuidString)
        XCTAssertEqual(stored[1].exercises.first?.sets.map(\.targetReps), [12, 12])
        XCTAssertEqual(stored[1].exercises.first?.sets.map(\.targetWeightKg), [60, 60])
    }

    func testApplyStillWritesTheOwnerPlanToPlannedPrescriptions() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date()); ctx.insert(session)

        planWithPartner(UUID()).apply(to: session)

        XCTAssertEqual(session.plannedPrescriptions.first?.exerciseName, "Bench Press")
        XCTAssertEqual(session.plannedPrescriptions.first?.sets.map(\.targetReps), [8, 6],
                       "The owner's plan must stay where every existing reader looks for it")
    }

    func testSoloPlanWritesNoPerformerPrescriptions() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date()); ctx.insert(session)

        EditablePlan(warmupMinutes: 0, cooldownMinutes: 0,
                     exercises: [EditableExercise(name: "Bench Press",
                                                  sets: [EditableSet(targetReps: 5, targetWeight: 100)],
                                                  notes: "")])
            .apply(to: session)

        XCTAssertTrue(session.plannedPerformerPrescriptions.isEmpty)
        XCTAssertEqual(session.plannedPrescriptions.count, 1)
    }

    func testFromSessionRoundTripsPerformerPlans() throws {
        let ctx = try makeContext()
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        let alex = try WorkoutRepository.findOrCreatePerson(named: "Alex", in: ctx)
        let session = WorkoutSession(title: "Push", date: Date()); ctx.insert(session)
        ctx.insert(SetEntry(weight: 100, reps: 8, order: 0, completedAt: session.date,
                            session: session, exercise: bench))
        let partnerSet = SetEntry(weight: 60, reps: 12, order: 1, completedAt: session.date,
                                  session: session, exercise: bench)
        partnerSet.performedBy = alex
        ctx.insert(partnerSet)
        planWithPartner(alex.id).apply(to: session)
        try ctx.save()

        let plans = EditablePlan.from(session: session).exercises.first?.performerPlans ?? []
        XCTAssertEqual(plans.map(\.name), ["Me", "Alex"])
        XCTAssertEqual(plans.last?.performerID, alex.id)
        XCTAssertEqual(plans.last?.sets.map(\.targetReps), [12, 12])
    }

    func testLegacySessionWithoutPerformerDataResolvesToTheOwnerPlan() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date()); ctx.insert(session)
        session.plannedPrescriptions = [PlannedExercisePrescription(
            exerciseName: "Bench Press",
            sets: [PlannedSetPrescription(targetReps: 5, targetWeightKg: 100)])]

        XCTAssertTrue(session.plannedPerformerPrescriptions.isEmpty)
        XCTAssertEqual(session.plannedPrescriptions(forPerformerID: nil).first?.sets.count, 1)
        XCTAssertEqual(session.plannedPrescriptions(forPerformerID: UUID()).first?.sets.first?.targetReps, 5,
                       "An unknown performer falls back to the owner's plan, as before this field existed")
        XCTAssertTrue(EditablePlan.from(session: session).exercises.allSatisfy { $0.performerPlans.isEmpty })
    }
}
