import XCTest
import CadenceCore
@testable import CadenceFeatures

/// Field test 2026-08-19 #1 and #3: what a performer's next set should be.
final class PerformerSetPlannerTests: XCTestCase {

    private func plan(_ reps: [Int], weight: Double? = nil) -> [PlannedSetPrescription] {
        reps.map { PlannedSetPrescription(targetReps: $0, targetWeightKg: weight) }
    }

    // MARK: - #1 the entered plan is the prescription

    func testExplicitPlanBeatsHistoryForRepsAndWeight() {
        let history = PerformerSetPlanner.History(
            repLadders: [[20, 20, 20]], firstWorkingWeightKg: 45)
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 1, performerPlan: plan([12, 12], weight: 40),
            ownerPlan: plan([5, 5], weight: 100), ownerLadder: [5, 5],
            isOwner: false, history: history)
        XCTAssertEqual(resolved.reps, 12)
        XCTAssertEqual(resolved.weightKg, 40)
    }

    func testPlannedRepsWithNoLoadFallBackToTheirOwnWorkingWeight() {
        let history = PerformerSetPlanner.History(firstWorkingWeightKg: 45)
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: plan([12]), ownerPlan: plan([5], weight: 100),
            ownerLadder: nil, isOwner: false, history: history)
        XCTAssertEqual(resolved.reps, 12)
        XCTAssertEqual(resolved.weightKg, 45, "A partner never inherits the owner's load")
    }

    func testPartnerNeverInheritsTheOwnersLoad() {
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil, ownerPlan: plan([5], weight: 100),
            ownerLadder: [5], isOwner: false, history: .empty)
        XCTAssertNil(resolved.weightKg)
        XCTAssertEqual(resolved.reps, 5, "With nothing else to go on, the owner's reps are the fallback")
    }

    func testOwnerDoesInheritTheirOwnPrescribedLoad() {
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil, ownerPlan: plan([5], weight: 100),
            ownerLadder: [5], isOwner: true, history: .empty)
        XCTAssertEqual(resolved.weightKg, 100)
    }

    func testSetsBeyondThePlanFallThroughToHistory() {
        let history = PerformerSetPlanner.History(
            repLadders: [[20, 18, 16]], firstWorkingWeightKg: 45)
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 2, performerPlan: plan([12]), ownerPlan: plan([5, 5, 5]),
            ownerLadder: nil, isOwner: false, history: history)
        XCTAssertEqual(resolved.reps, 16)
        XCTAssertEqual(resolved.weightKg, 45)
    }

    // MARK: - #3 habitual reps

    func testHabitualRepsIsTheModalWorkingRepCount() {
        let ladders = [[20, 20, 20], [20, 20], [12, 20, 20]]
        XCTAssertEqual(PerformerSetPlanner.habitualReps(generalRepLadders: ladders), 20)
    }

    func testHabitualRepsBreaksTiesOnRecency() {
        // 8 and 12 each appear twice; 12 was logged most recently.
        let ladders = [[8, 8], [12, 12]]
        XCTAssertEqual(PerformerSetPlanner.habitualReps(generalRepLadders: ladders), 12)
    }

    func testHabitualRepsIsNilWithoutHistory() {
        XCTAssertNil(PerformerSetPlanner.habitualReps(generalRepLadders: []))
        XCTAssertNil(PerformerSetPlanner.habitualReps(generalRepLadders: [[], [0]]))
    }

    func testNewMovementUsesHabitualRepsRatherThanTheGenericFive() {
        let history = PerformerSetPlanner.History(generalRepLadders: [[20, 20, 20], [20, 20]])
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil, ownerPlan: plan([5]),
            ownerLadder: [5], isOwner: false, history: history)
        XCTAssertEqual(resolved.reps, 20)
        XCTAssertNil(resolved.weightKg, "A brand-new movement has no load to suggest")
    }

    func testMovementHistoryStillOutranksTheGeneralHabit() {
        let history = PerformerSetPlanner.History(
            repLadders: [[8, 8, 8]], generalRepLadders: [[20, 20, 20]])
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil, ownerPlan: plan([5]),
            ownerLadder: nil, isOwner: false, history: history)
        XCTAssertEqual(resolved.reps, 8)
    }

    func testAbsolutelyNothingKnownFallsBackToTheDefault() {
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 0, performerPlan: nil, ownerPlan: [], ownerLadder: nil,
            isOwner: true, history: .empty)
        XCTAssertEqual(resolved.reps, PerformerSetPlanner.defaultReps)
        XCTAssertNil(resolved.weightKg)
    }

    // MARK: - Within-session continuation

    func testLaterSetsFollowWhatWasAlreadyLoggedToday() {
        let history = PerformerSetPlanner.History(repsLoggedThisSession: [20, 20])
        let resolved = PerformerSetPlanner.resolve(
            setIndex: 2, performerPlan: nil, ownerPlan: [], ownerLadder: nil,
            isOwner: false, history: history)
        XCTAssertEqual(resolved.reps, 20)
    }

    func testHasMovementHistoryReflectsOnlyThisMovement() {
        XCTAssertFalse(PerformerSetPlanner.History(generalRepLadders: [[20]]).hasMovementHistory)
        XCTAssertTrue(PerformerSetPlanner.History(repLadders: [[20]]).hasMovementHistory)
        XCTAssertTrue(PerformerSetPlanner.History(repsLoggedThisSession: [20]).hasMovementHistory)
    }
}
