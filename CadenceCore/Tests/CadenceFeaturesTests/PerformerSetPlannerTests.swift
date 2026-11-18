import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

/// Field test 2026-08-19 #1 and #3: what a performer's next set should be.
struct PerformerSetPlannerTests {

    private func plan(_ reps: [Int], weight: Double? = nil) -> [PlannedSetPrescription] {
        reps.map { PlannedSetPrescription(targetReps: $0, targetWeightKg: weight) }
    }

    // MARK: - #1 the entered plan is the prescription

    @Test func explicitPlanBeatsHistoryForRepsAndWeight() {
        let history = PerformerSetPlanner.History(
            repLadders: [[20, 20, 20]], firstWorkingWeightKg: 45)
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 1, performerPlan: plan([12, 12], weight: 40),
            ownerPlan: plan([5, 5], weight: 100), ownerLadder: [5, 5],
            isOwner: false, history: history)
        #expect(resolved.reps == 12)
        #expect(resolved.weightKg == 40)
    }

    @Test func plannedRepsWithNoLoadFallBackToTheirOwnWorkingWeight() {
        let history = PerformerSetPlanner.History(firstWorkingWeightKg: 45)
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: plan([12]), ownerPlan: plan([5], weight: 100),
            ownerLadder: nil, isOwner: false, history: history)
        #expect(resolved.reps == 12)
        #expect(resolved.weightKg == 45, "A partner never inherits the owner's load")
    }

    @Test func partnerNeverInheritsTheOwnersLoad() {
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil, ownerPlan: plan([5], weight: 100),
            ownerLadder: [5], isOwner: false, history: .empty)
        #expect(resolved.weightKg == nil)
        #expect(resolved.reps == 5, "With nothing else to go on, the owner's reps are the fallback")
    }

    @Test func ownerDoesInheritTheirOwnPrescribedLoad() {
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil, ownerPlan: plan([5], weight: 100),
            ownerLadder: [5], isOwner: true, history: .empty)
        #expect(resolved.weightKg == 100)
    }

    @Test func previousSetWeightBeatsHistoricalEstimateWhenNoSetLoadIsPlanned() {
        let history = PerformerSetPlanner.History(
            repsLoggedThisSession: [8],
            lastWeightThisSessionKg: 75,
            weightSamples: [SetSample(weight: 100, reps: 12)])
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 1, performerPlan: nil, ownerPlan: [], ownerLadder: nil,
            isOwner: false, history: history)
        #expect(resolved.weightKg == 75)
        #expect(resolved.weightBasis == .currentSession)
    }

    @Test func ownerPlanWeightBeatsPreviousSetWeight() {
        let history = PerformerSetPlanner.History(lastWeightThisSessionKg: 75)
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 1, performerPlan: nil, ownerPlan: plan([8, 8], weight: 80),
            ownerLadder: nil, isOwner: true, history: history)
        #expect(resolved.weightKg == 80)
        #expect(resolved.weightBasis == .ownerPlan)
    }

    @Test func setsBeyondThePlanFallThroughToHistory() {
        let history = PerformerSetPlanner.History(
            repLadders: [[20, 18, 16]], firstWorkingWeightKg: 45)
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 2, performerPlan: plan([12]), ownerPlan: plan([5, 5, 5]),
            ownerLadder: nil, isOwner: false, history: history)
        #expect(resolved.reps == 16)
        #expect(resolved.weightKg == 45)
    }

    // MARK: - #3 habitual reps

    @Test func habitualRepsIsTheModalWorkingRepCount() {
        let ladders = [[20, 20, 20], [20, 20], [12, 20, 20]]
        #expect(PerformerSetPlanner.habitualReps(generalRepLadders: ladders) == 20)
    }

    @Test func habitualRepsBreaksTiesOnRecency() {
        // 8 and 12 each appear twice; 12 was logged most recently.
        let ladders = [[8, 8], [12, 12]]
        #expect(PerformerSetPlanner.habitualReps(generalRepLadders: ladders) == 12)
    }

    @Test func habitualRepsIsNilWithoutHistory() {
        #expect(PerformerSetPlanner.habitualReps(generalRepLadders: []) == nil)
        #expect(PerformerSetPlanner.habitualReps(generalRepLadders: [[], [0]]) == nil)
    }

    @Test func newMovementUsesHabitualRepsRatherThanTheGenericFive() {
        let history = PerformerSetPlanner.History(generalRepLadders: [[20, 20, 20], [20, 20]])
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil, ownerPlan: plan([5]),
            ownerLadder: [5], isOwner: false, history: history)
        #expect(resolved.reps == 20)
        #expect(resolved.weightKg == nil, "A brand-new movement has no load to suggest")
    }

    @Test func movementHistoryStillOutranksTheGeneralHabit() {
        let history = PerformerSetPlanner.History(
            repLadders: [[8, 8, 8]], generalRepLadders: [[20, 20, 20]])
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil, ownerPlan: plan([5]),
            ownerLadder: nil, isOwner: false, history: history)
        #expect(resolved.reps == 8)
    }

    @Test func absolutelyNothingKnownFallsBackToTheDefault() {
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil, ownerPlan: [], ownerLadder: nil,
            isOwner: true, history: .empty)
        #expect(resolved.reps == PerformerSetPlanner.defaultReps)
        #expect(resolved.weightKg == nil)
    }

    @Test func historyWeightCarriesItsBasisAndPreservesExactHistoricalLoad() {
        let history = PerformerSetPlanner.History(
            firstWorkingWeightKg: 15.08,
            weightSamples: [SetSample(weight: 15.08, reps: 8)])
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil,
            ownerPlan: plan([8]), ownerLadder: nil,
            isOwner: false, history: history)

        #expect(resolved.weightBasis == .exactHistory)
        #expect(abs((resolved.weightKg ?? 0) - 15.08) <= 0.001)
        #expect(abs(SessionViewModel.roundedInferredWeightKg(
            resolved.weightKg ?? 0, unit: .pounds, basis: resolved.weightBasis) - 15.08) <= 0.001)
    }

    @Test func priorHistoricalWeightIsExactStartingPointWhenTargetRepsDiffer() {
        let history = PerformerSetPlanner.History(
            firstWorkingWeightKg: 57,
            weightSamples: [SetSample(weight: 57, reps: 5)])
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: plan([8]), ownerPlan: [], ownerLadder: nil,
            isOwner: false, history: history)

        #expect(resolved.weightBasis == .priorHistory)
        #expect(resolved.weightKg == 57,
                "A real historical load must not be replaced by an estimated or rounded load")
    }

    // MARK: - Within-session continuation

    @Test func laterSetsFollowWhatWasAlreadyLoggedToday() {
        let history = PerformerSetPlanner.History(repsLoggedThisSession: [20, 20])
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 2, performerPlan: nil, ownerPlan: [], ownerLadder: nil,
            isOwner: false, history: history)
        #expect(resolved.reps == 20)
    }

    @Test func hasMovementHistoryReflectsOnlyThisMovement() {
        #expect(!PerformerSetPlanner.History(generalRepLadders: [[20]]).hasMovementHistory)
        #expect(PerformerSetPlanner.History(repLadders: [[20]]).hasMovementHistory)
        #expect(PerformerSetPlanner.History(repsLoggedThisSession: [20]).hasMovementHistory)
    }
}

struct PerformerSetPlannerLastWorkingSetTests {
    private let lastSet = SetSample(weight: 56.699, reps: 8)

    @Test func lastPriorWorkingSetBeatsRepPatternAndEstimatedLoadWithoutPlan() {
        let history = PerformerSetPlanner.History(
            repLadders: [[12, 10, 8]], firstWorkingWeightKg: 88.5,
            weightSamples: [SetSample(weight: 88.5, reps: 12)], lastPriorWorkingSet: lastSet)
        let r = PerformerSetPlanner.resolve(setIndex: 0, performerPlan: nil, ownerPlan: [],
                                            ownerLadder: nil, isOwner: true, history: history)
        #expect(r.reps == 8)
        #expect(abs((r.weightKg ?? 0) - 56.699) <= 0.0001)
        #expect(r.weightBasis == .lastWorkingSet)
    }

    @Test func explicitPlanOverridesFieldByField() {
        let history = PerformerSetPlanner.History(lastPriorWorkingSet: lastSet)
        let repsOnly = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: [PlannedSetPrescription(targetReps: 6, targetWeightKg: nil)],
            ownerPlan: [], ownerLadder: nil, isOwner: true, history: history)
        #expect(repsOnly.reps == 6)
        #expect(abs((repsOnly.weightKg ?? 0) - 56.699) <= 0.0001)
        let full = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: [PlannedSetPrescription(targetReps: 6, targetWeightKg: 88.5)],
            ownerPlan: [], ownerLadder: nil, isOwner: true, history: history)
        #expect(full.reps == 6)
        #expect(full.weightKg == 88.5)
    }

    @Test func extraSetBeyondPlanReturnsToHistory() {
        let history = PerformerSetPlanner.History(lastPriorWorkingSet: lastSet)
        let r = PerformerSetPlanner.resolve(
            setIndex: 1, performerPlan: [PlannedSetPrescription(targetReps: 6, targetWeightKg: 88.5)],
            ownerPlan: [], ownerLadder: nil, isOwner: true, history: history)
        #expect(r.reps == 8)
        #expect(abs((r.weightKg ?? 0) - 56.699) <= 0.0001)
    }

    @Test func partnerIgnoresOwnerPlanAndUsesOwnLastSet() {
        let history = PerformerSetPlanner.History(
            lastPriorWorkingSet: SetSample(weight: 40, reps: 12))
        let r = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil,
            ownerPlan: [PlannedSetPrescription(targetReps: 6, targetWeightKg: 88.5)],
            ownerLadder: [6], isOwner: false, history: history)
        #expect(r.reps == 12)
        #expect(r.weightKg == 40)
    }
}
