#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

@MainActor
struct EditablePlanTests {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test func templateConvertsToAStartableEditablePlan() throws {
        let ctx = try makeContext()
        let template = try WorkoutRepository.createTemplate(
            name: "Push Day", exercises: [("Bench Press", 3, 8)], in: ctx)

        let plan = EditablePlan.from(template: template, warmupMinutes: 5, cooldownMinutes: 3)
        #expect(plan.title == "Push Day")
        #expect(plan.warmupMinutes == 5)
        #expect(plan.cooldownMinutes == 3)
        #expect(plan.exercises.first?.name == "Bench Press")
        #expect(plan.exercises.first?.sets.map(\.targetReps) == [8, 8, 8])
    }

    @Test func fromSessionCopiesOwnerSets() throws {
        let ctx = try makeContext()
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        let s = WorkoutSession(title: "Push Day", date: Date()); ctx.insert(s)
        ctx.insert(SetEntry(weight: 100, reps: 5, order: 0, completedAt: s.date, session: s, exercise: bench))
        ctx.insert(SetEntry(weight: 100, reps: 4, order: 1, completedAt: s.date, session: s, exercise: bench))
        try ctx.save()

        let plan = EditablePlan.from(session: s)
        #expect(plan.title == "Push Day")
        #expect(plan.exercises.count == 1)
        #expect(plan.exercises.first?.sets.count == 2)
        #expect(plan.exercises.first?.sets.map(\.targetReps) == [5, 4])
    }

    @Test func fromPlanSeedsSetsFromLadder() {
        let item = PlanItem(id: 1, movement: "Back Squat", reps: 5, targetSets: nil)
        let wp = WorkoutPlan(id: "preset", name: "5x5", source: .strengthPreset,
                             scheme: .strength, items: [item])
        let plan = EditablePlan.from(plan: wp, ladder: [5, 5, 5], unit: .kilograms)
        #expect(plan.title == "5x5")
        #expect(plan.exercises.count == 1)
        #expect(plan.exercises.first?.sets.count == 3)
        #expect(plan.exercises.first?.sets.map(\.targetReps) == [5, 5, 5])
    }

    @Test func fromPlanWithoutLadderDefaultsToThreeSets() {
        let item = PlanItem(id: 1, movement: "Back Squat", reps: 8, targetSets: nil)
        let wp = WorkoutPlan(id: "p", name: "P", source: .strengthPreset, scheme: .strength, items: [item])
        let plan = EditablePlan.from(plan: wp, ladder: nil, unit: .kilograms)
        #expect(plan.exercises.first?.sets.count == 3)
        #expect(plan.exercises.first?.sets.map(\.targetReps) == [8, 8, 8])
    }

    /// Field test 2026-08-18 #2: a resolved coach load must survive into the
    /// editable plan, and a bodyweight movement must stay unweighted (D4).
    @Test func coachPlanCarriesResolvedWeightsIntoEditableSets() {
        let session = CoachSession(
            id: "c2", kind: .strength, title: "Pull",
            exercises: [CoachSession.RecommendedExercise(
                name: "Standing Dumbbell Upright Row",
                sets: 3, repsLow: 12, loadKg: 22.5, rir: 2)])
        let plan = EditablePlan.from(coach: session)
        let sets = plan?.exercises.first?.sets ?? []
        #expect(sets.count == 3)
        #expect(sets.allSatisfy { $0.targetWeight == 22.5 },
                       "a resolved load must reach every planned set, not render as BW")
    }

    @Test func coachPlanBodyweightExerciseHasNilTargetWeight() {
        let session = CoachSession(
            id: "c3", kind: .strength, title: "Push",
            exercises: [CoachSession.RecommendedExercise(name: "Push-Up", sets: 3, repsLow: 20, rir: 2)])
        let plan = EditablePlan.from(coach: session)
        #expect(plan?.exercises.first?.sets.allSatisfy { $0.targetWeight == nil } == true)
        #expect(ExerciseLoading.isBodyweight(named: "Push-Up"),
                      "which is why the editor is allowed to print BW for it")
    }

    @Test func fromCoachSessionMapsExercises() {
        let ex = CoachSession.RecommendedExercise(name: "Bench Press", sets: 3, repsLow: 8, loadKg: 60, rir: 2)
        let session = CoachSession(id: "c1", kind: .strength, title: "Upper", exercises: [ex])
        let plan = EditablePlan.from(coach: session)
        #expect(plan != nil)
        #expect(plan?.title == "Upper")
        #expect(plan?.warmupMinutes == 5)
        #expect(plan?.exercises.first?.sets.count == 3)
        #expect(plan?.exercises.first?.sets.allSatisfy { $0.targetReps == 8 } == true)
        #expect(plan?.exercises.first?.sets.allSatisfy { $0.targetWeight == 60 } == true)
        #expect(plan?.exercises.first?.notes == "Target ≤2 RIR")
    }

    @Test func fromCoachSessionNilWhenNoExercises() {
        let session = CoachSession(id: "c2", kind: .strength, title: "Empty", exercises: nil)
        #expect(EditablePlan.from(coach: session) == nil)
    }

    @Test func applyPreservesEachExerciseSetLadderAndWeight() {
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
        #expect(session.plannedPrescriptions == [
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

    @Test func unifiedSessionPreservesDraftIDsLoadsAndRIRIntent() {
        let setID = UUID()
        let plan = EditablePlan(
            title: "Unified draft",
            warmupMinutes: 0,
            cooldownMinutes: 0,
            exercises: [EditableExercise(
                name: "Bench Press",
                sets: [EditableSet(id: setID, targetReps: 5, targetWeight: 75,
                                   loadMode: .percentageOfOneRepMax,
                                   oneRepMaxPercent: 75)],
                notes: "Target ≤2 RIR")])
        let unified = plan.unifiedSession()
        guard case let .strength(item) = unified.items.first,
              let set = item.sets.first else {
            Issue.record("editable strength draft should convert to a strength item")
            return
        }

        #expect(item.id == plan.exercises[0].id)
        #expect(set.id == setID)
        #expect(set.targetRIR == 2)
        #expect(set.load == .percent1RM(percent: 0.75, calculatedWeight: 75))
        #expect(item.exerciseKey.raw ==
                       ExerciseLibrary.template(matching: "Bench Press")?.sourceExerciseID
                       ?? ExerciseLibrary.lookupKey("Bench Press"))
    }

    @Test func applyCarriesEngineProvenanceIntoSession() {
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

        #expect(session.enginePlanId == "generated-plan")
        #expect(session.engineRevisionId == "r1")
        #expect(session.enginePlanJSON == json)
    }

    @Test func normalizedPartnerIDsDropsOwnerOnly() {
        let owner = UUID()
        #expect(EditablePlan.normalizedPartnerIDs([owner], ownerID: owner) == [])
    }

    @Test func normalizedPartnerIDsKeepsPartnersAndDedupes() {
        let owner = UUID(); let a = UUID(); let b = UUID()
        let result = EditablePlan.normalizedPartnerIDs([owner, a, a, b], ownerID: owner)
        #expect(result == [owner, a, b])
    }

    // Coach-user-control Phase 5 — "do a strength workout anyway" must always
    // produce a real, editable full-body plan, even with zero history.
    @Test func strengthAnywayProducesEditablePlan() {
        let facts = CoachFacts.make(from: [], goal: .hypertrophy,
                                    experience: .intermediate, now: Date())
        let plan = EditablePlan.strengthAnyway(facts: facts)
        #expect(plan != nil, "Strength-anyway must offer a plan even with no history")
        #expect(!(plan?.exercises.isEmpty ?? true))
        #expect(plan?.title == "Strength session")
        #expect(plan?.exercises.allSatisfy { !$0.sets.isEmpty } ?? false,
                      "Every exercise carries a concrete set prescription")
    }

    @Test func strengthAnywayUsesGoalRepScheme() {
        let facts = CoachFacts.make(from: [], goal: .strength,
                                    experience: .intermediate, now: Date())
        let plan = EditablePlan.strengthAnyway(facts: facts)
        let reps = plan?.exercises.first?.sets.map(\.targetReps) ?? []
        #expect(!reps.isEmpty)
        #expect(reps.allSatisfy { TrainingGoal.strength.repRange.contains($0) },
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

    @Test func applyWritesPerformerPrescriptionsForEveryRosterMember() throws {
        let ctx = try makeContext()
        let partnerID = UUID()
        let session = WorkoutSession(title: "Push", date: Date()); ctx.insert(session)

        planWithPartner(partnerID).apply(to: session)

        let stored = session.plannedPerformerPrescriptions
        #expect(stored.count == 2)
        #expect(stored[0].performerID == nil, "The owner is stored first, keyed by nil")
        #expect(stored[1].performerID == partnerID.uuidString)
        #expect(stored[1].exercises.first?.sets.map(\.targetReps) == [12, 12])
        #expect(stored[1].exercises.first?.sets.map(\.targetWeightKg) == [60, 60])
    }

    @Test func applyStillWritesTheOwnerPlanToPlannedPrescriptions() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date()); ctx.insert(session)

        planWithPartner(UUID()).apply(to: session)

        #expect(session.plannedPrescriptions.first?.exerciseName == "Bench Press")
        #expect(session.plannedPrescriptions.first?.sets.map(\.targetReps) == [8, 6],
                       "The owner's plan must stay where every existing reader looks for it")
    }

    @Test func soloPlanWritesNoPerformerPrescriptions() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date()); ctx.insert(session)

        EditablePlan(warmupMinutes: 0, cooldownMinutes: 0,
                     exercises: [EditableExercise(name: "Bench Press",
                                                  sets: [EditableSet(targetReps: 5, targetWeight: 100)],
                                                  notes: "")])
            .apply(to: session)

        #expect(session.plannedPerformerPrescriptions.isEmpty)
        #expect(session.plannedPrescriptions.count == 1)
    }

    @Test func fromSessionRoundTripsPerformerPlans() throws {
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
        #expect(plans.map(\.name) == ["Me", "Alex"])
        #expect(plans.last?.performerID == alex.id)
        #expect(plans.last?.sets.map(\.targetReps) == [12, 12])
    }

    @Test func legacySessionWithoutPerformerDataResolvesToTheOwnerPlan() throws {
        let ctx = try makeContext()
        let session = WorkoutSession(title: "Push", date: Date()); ctx.insert(session)
        session.plannedPrescriptions = [PlannedExercisePrescription(
            exerciseName: "Bench Press",
            sets: [PlannedSetPrescription(targetReps: 5, targetWeightKg: 100)])]

        #expect(session.plannedPerformerPrescriptions.isEmpty)
        #expect(session.plannedPrescriptions(forPerformerID: nil).first?.sets.count == 1)
        #expect(session.plannedPrescriptions(forPerformerID: UUID()).first?.sets.first?.targetReps == 5,
                       "An unknown performer falls back to the owner's plan, as before this field existed")
        #expect(EditablePlan.from(session: session).exercises.allSatisfy { $0.performerPlans.isEmpty })
    }
}
#endif
