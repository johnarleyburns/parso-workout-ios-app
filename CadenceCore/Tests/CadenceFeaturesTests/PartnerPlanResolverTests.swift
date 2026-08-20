import XCTest
import CadenceCore
@testable import CadenceFeatures

/// Field test 2026-08-18 #4 (decisions D12/D13): a training partner is coached
/// on the OWNER's exercises and set count, personalized only by reps/weights
/// drawn from that partner's own history — never the owner's weight.
final class PartnerPlanResolverTests: XCTestCase {

    private let alex = UUID()
    private let sam = UUID()

    private func ownerSets(_ reps: [Int], weight: Double? = 100) -> [EditableSet] {
        reps.map { EditableSet(targetReps: $0, targetWeight: weight) }
    }

    private func plan(_ exercises: [EditableExercise]) -> EditablePlan {
        EditablePlan(warmupMinutes: 0, cooldownMinutes: 0, exercises: exercises)
    }

    // MARK: - sets(forOwnerSets:history:)

    func testPartnerWithExactExerciseHistoryGetsTheirOwnLadderAndWeight() {
        let history = PartnerPlanResolver.ExerciseHistory(
            lastSets: [.init(weightKg: 60, reps: 8),
                       .init(weightKg: 62.5, reps: 6),
                       .init(weightKg: 65, reps: 5)],
            firstWorkingWeightKg: 60)

        let resolved = PartnerPlanResolver.sets(forOwnerSets: ownerSets([8, 6, 5]), history: history)

        XCTAssertEqual(resolved.map(\.targetReps), [8, 6, 5])
        XCTAssertEqual(resolved.map(\.targetWeight), [60, 62.5, 65])
    }

    func testPartnerWeightNeverInheritsTheOwnersWeight() {
        let owner = ownerSets([10, 8, 6], weight: 140)
        let resolved = PartnerPlanResolver.sets(forOwnerSets: owner, history: .empty)

        XCTAssertEqual(resolved.compactMap(\.targetWeight), [],
                       "A partner with no history inherited the owner's weight")
    }

    func testPartnerWithNoExerciseHistoryUsesTheirGeneralRepPattern() {
        let history = PartnerPlanResolver.ExerciseHistory(generalRepLadders: [[15, 15], [12, 10, 8]])
        let resolved = PartnerPlanResolver.sets(forOwnerSets: ownerSets([5, 5, 5]), history: history)

        XCTAssertEqual(resolved.map(\.targetReps), [12, 10, 8], "The most recent pattern should win")
        XCTAssertEqual(resolved.compactMap(\.targetWeight), [],
                       "A general rep pattern says nothing about load")
    }

    func testPartnerWithNoHistoryAtAllUsesOwnerRepsWithNoWeight() {
        let resolved = PartnerPlanResolver.sets(forOwnerSets: ownerSets([12, 10, 8]), history: .empty)

        XCTAssertEqual(resolved.map(\.targetReps), [12, 10, 8])
        XCTAssertTrue(resolved.allSatisfy { $0.targetWeight == nil })
    }

    func testExerciseLadderIsUsedWhenTheLastSessionHasNoLoggedSets() {
        let history = PartnerPlanResolver.ExerciseHistory(
            repLadders: [[10, 10], [8, 6]],
            firstWorkingWeightKg: 42.5)
        let resolved = PartnerPlanResolver.sets(forOwnerSets: ownerSets([5, 5]), history: history)

        XCTAssertEqual(resolved.map(\.targetReps), [8, 6])
        XCTAssertEqual(resolved.map(\.targetWeight), [42.5, 42.5])
    }

    func testResolvedSetCountAlwaysMatchesTheOwnersSetCount() {
        let history = PartnerPlanResolver.ExerciseHistory(
            lastSets: [.init(weightKg: 50, reps: 10)],
            firstWorkingWeightKg: 50)

        for count in 1...6 {
            let owner = ownerSets(Array(repeating: 8, count: count))
            XCTAssertEqual(PartnerPlanResolver.sets(forOwnerSets: owner, history: history).count, count)
        }
        XCTAssertTrue(PartnerPlanResolver.sets(forOwnerSets: [], history: history).isEmpty)
    }

    func testShorterPartnerHistoryRepeatsTheLastLoggedSet() {
        let history = PartnerPlanResolver.ExerciseHistory(
            lastSets: [.init(weightKg: 40, reps: 12), .init(weightKg: 45, reps: 10)],
            firstWorkingWeightKg: 40)
        let resolved = PartnerPlanResolver.sets(forOwnerSets: ownerSets([12, 10, 8, 8]), history: history)

        XCTAssertEqual(resolved.map(\.targetReps), [12, 10, 10, 10])
        XCTAssertEqual(resolved.map(\.targetWeight), [40, 45, 45, 45])
    }

    func testLongerPartnerHistoryIsTruncatedToTheOwnersSetCount() {
        let history = PartnerPlanResolver.ExerciseHistory(
            lastSets: (1...5).map { .init(weightKg: Double(40 + $0), reps: 12 - $0) })
        let resolved = PartnerPlanResolver.sets(forOwnerSets: ownerSets([10, 10]), history: history)

        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved.map(\.targetReps), [11, 10])
    }

    func testZeroOrNegativeRepsAreTreatedAsMissing() {
        let history = PartnerPlanResolver.ExerciseHistory(
            lastSets: [.init(weightKg: 60, reps: 0), .init(weightKg: 60, reps: -3)],
            repLadders: [[9, 9]],
            firstWorkingWeightKg: 60)
        let resolved = PartnerPlanResolver.sets(forOwnerSets: ownerSets([5, 5]), history: history)

        XCTAssertEqual(resolved.map(\.targetReps), [9, 9],
                       "Zero/negative logged reps should fall through to the rep ladder")
    }

    func testAWeightlessLoggedSetFallsBackToTheirFirstWorkingWeight() {
        let history = PartnerPlanResolver.ExerciseHistory(
            lastSets: [.init(weightKg: 0, reps: 10), .init(weightKg: 55, reps: 8)],
            firstWorkingWeightKg: 52.5)
        let resolved = PartnerPlanResolver.sets(forOwnerSets: ownerSets([10, 8]), history: history)

        XCTAssertEqual(resolved.map(\.targetWeight), [52.5, 55])
    }

    // MARK: - fill(plan:roster:history:)

    func testOwnerIsAlwaysTheFirstPerformerPlan() {
        let filled = PartnerPlanResolver.fill(
            plan: plan([EditableExercise(name: "Bench Press", sets: ownerSets([8, 6]), notes: "")]),
            roster: [.init(performerID: nil, name: "Me"), .init(performerID: alex, name: "Alex")],
            history: { _, _ in .empty })

        let plans = filled.exercises[0].performerPlans
        XCTAssertEqual(plans.map(\.name), ["Me", "Alex"])
        XCTAssertTrue(plans[0].isMe)
        XCTAssertEqual(plans[0].sets.map(\.targetReps), [8, 6])
        XCTAssertEqual(plans[0].sets.map(\.targetWeight), [100, 100],
                       "The owner's own plan is copied verbatim, weights included")
    }

    func testFillIsIdempotent() {
        let source = plan([EditableExercise(name: "Bench Press", sets: ownerSets([8, 6, 5]), notes: ""),
                           EditableExercise(name: "Row", sets: ownerSets([10, 10]), notes: "")])
        let roster: [PartnerPlanResolver.RosterMember] = [
            .init(performerID: nil, name: "Me"), .init(performerID: alex, name: "Alex")
        ]
        let history: (String, UUID?) -> PartnerPlanResolver.ExerciseHistory = { name, _ in
            name == "Row" ? .init(lastSets: [.init(weightKg: 30, reps: 12)]) : .empty
        }

        let once = PartnerPlanResolver.fill(plan: source, roster: roster, history: history)
        let twice = PartnerPlanResolver.fill(plan: once, roster: roster, history: history)

        XCTAssertEqual(once, twice, "Re-resolving an unchanged roster changed the plan (or its identity)")
    }

    func testRemovingAPartnerDropsTheirPerformerPlan() {
        let source = plan([EditableExercise(name: "Bench Press", sets: ownerSets([8, 6]), notes: "")])
        let withPartners = PartnerPlanResolver.fill(
            plan: source,
            roster: [.init(performerID: nil, name: "Me"),
                     .init(performerID: alex, name: "Alex"),
                     .init(performerID: sam, name: "Sam")],
            history: { _, _ in .empty })
        XCTAssertEqual(withPartners.exercises[0].performerPlans.count, 3)

        let oneRemoved = PartnerPlanResolver.fill(
            plan: withPartners,
            roster: [.init(performerID: nil, name: "Me"), .init(performerID: alex, name: "Alex")],
            history: { _, _ in .empty })
        XCTAssertEqual(oneRemoved.exercises[0].performerPlans.map(\.name), ["Me", "Alex"])

        let solo = PartnerPlanResolver.fill(
            plan: oneRemoved,
            roster: [.init(performerID: nil, name: "Me")],
            history: { _, _ in .empty })
        XCTAssertTrue(solo.exercises[0].performerPlans.isEmpty,
                      "A solo roster should leave the plan exactly as a solo user's")
    }

    func testAddingAPartnerLeavesTheOwnerPlanUntouched() {
        let source = plan([EditableExercise(name: "Bench Press", sets: ownerSets([8, 6, 5]), notes: "")])
        let filled = PartnerPlanResolver.fill(
            plan: source,
            roster: [.init(performerID: nil, name: "Me"), .init(performerID: alex, name: "Alex")],
            history: { _, _ in .init(lastSets: [.init(weightKg: 60, reps: 12)]) })

        XCTAssertEqual(filled.exercises[0].sets, source.exercises[0].sets,
                       "Adding a partner rewrote the owner's own sets")
        XCTAssertEqual(filled.exercises[0].performerPlans[1].sets.map(\.targetReps), [12, 12, 12])
    }

    func testTheCoachNeverAddsOrRemovesAnExerciseForAPartner() {
        let source = plan([EditableExercise(name: "Bench Press", sets: ownerSets([8]), notes: ""),
                           EditableExercise(name: "Squat", sets: ownerSets([5, 5]), notes: "")])
        let filled = PartnerPlanResolver.fill(
            plan: source,
            roster: [.init(performerID: nil, name: "Me"), .init(performerID: alex, name: "Alex")],
            history: { _, _ in .empty })

        XCTAssertEqual(filled.exercises.map(\.name), ["Bench Press", "Squat"])
        for exercise in filled.exercises {
            for performerPlan in exercise.performerPlans {
                XCTAssertEqual(performerPlan.sets.count, exercise.sets.count)
            }
        }
    }

    func testBodyweightExerciseResolvesWithNilWeightForEveryPerformer() {
        let source = plan([EditableExercise(name: "Pull Up",
                                            sets: ownerSets([10, 8], weight: nil),
                                            notes: "")])
        let filled = PartnerPlanResolver.fill(
            plan: source,
            roster: [.init(performerID: nil, name: "Me"), .init(performerID: alex, name: "Alex")],
            history: { _, _ in .init(lastSets: [.init(weightKg: 0, reps: 6)]) })

        for performerPlan in filled.exercises[0].performerPlans {
            XCTAssertTrue(performerPlan.sets.allSatisfy { $0.targetWeight == nil },
                          "\(performerPlan.name) got a weight for a bodyweight movement")
        }
    }

    func testEachPartnerIsResolvedFromTheirOwnHistory() {
        let filled = PartnerPlanResolver.fill(
            plan: plan([EditableExercise(name: "Bench Press", sets: ownerSets([8, 8]), notes: "")]),
            roster: [.init(performerID: nil, name: "Me"),
                     .init(performerID: alex, name: "Alex"),
                     .init(performerID: sam, name: "Sam")],
            history: { [alex] _, performerID in
                performerID == alex
                    ? .init(lastSets: [.init(weightKg: 60, reps: 12)], firstWorkingWeightKg: 60)
                    : .init(lastSets: [.init(weightKg: 25, reps: 15)], firstWorkingWeightKg: 25)
            })

        let plans = filled.exercises[0].performerPlans
        XCTAssertEqual(plans[1].sets.map(\.targetWeight), [60, 60])
        XCTAssertEqual(plans[2].sets.map(\.targetReps), [15, 15])
    }

    // MARK: - aligned(_:) — set-count maintenance between re-resolutions

    private func filledExercise() -> EditableExercise {
        PartnerPlanResolver.fill(
            plan: plan([EditableExercise(name: "Bench Press", sets: ownerSets([8, 6]), notes: "")]),
            roster: [.init(performerID: nil, name: "Me"), .init(performerID: alex, name: "Alex")],
            history: { _, _ in .init(lastSets: [.init(weightKg: 60, reps: 12)], firstWorkingWeightKg: 60) }
        ).exercises[0]
    }

    func testAligningAfterTheOwnerAddsASetExtendsEveryPartner() {
        var exercise = filledExercise()
        exercise.sets.append(EditableSet(targetReps: 4, targetWeight: 110))

        let aligned = PartnerPlanResolver.aligned(exercise)

        XCTAssertEqual(aligned.performerPlans[0].sets.map(\.targetReps), [8, 6, 4],
                       "The owner's entry mirrors their own sets exactly")
        XCTAssertEqual(aligned.performerPlans[1].sets.map(\.targetReps), [12, 12, 12],
                       "A partner's extra set repeats their own last planned set")
        XCTAssertEqual(aligned.performerPlans[1].sets.map(\.targetWeight), [60, 60, 60],
                       "and never picks up the owner's weight")
    }

    func testAligningAfterTheOwnerRemovesASetTruncatesEveryPartner() {
        var exercise = filledExercise()
        exercise.sets.removeLast()

        let aligned = PartnerPlanResolver.aligned(exercise)

        for performerPlan in aligned.performerPlans {
            XCTAssertEqual(performerPlan.sets.count, 1)
        }
    }

    func testAligningASoloExerciseChangesNothing() {
        let solo = EditableExercise(name: "Bench Press", sets: ownerSets([8, 6]), notes: "")
        XCTAssertEqual(PartnerPlanResolver.aligned(solo), solo)
    }

    // MARK: - Owner seed (field test 2026-08-19 #1)

    func testOwnerSeedReproducesTheirLastSessionOnTheLift() {
        let history = PartnerPlanResolver.ExerciseHistory(
            lastSets: [.init(weightKg: 100, reps: 5), .init(weightKg: 100, reps: 3)],
            firstWorkingWeightKg: 100)
        let seed = PartnerPlanResolver.ownerSeedSets(history: history, defaultReps: 10)
        XCTAssertEqual(seed.map(\.targetReps), [5, 3])
        XCTAssertEqual(seed.map(\.targetWeight), [100, 100])
    }

    func testOwnerSeedFallsBackToTheirRepLadderThenTheirHabit() {
        let ladderOnly = PartnerPlanResolver.ExerciseHistory(
            repLadders: [[12, 10, 8]], firstWorkingWeightKg: 40)
        XCTAssertEqual(PartnerPlanResolver.ownerSeedSets(history: ladderOnly, defaultReps: 10)
                        .map(\.targetReps), [12, 10, 8])

        let habitOnly = PartnerPlanResolver.ExerciseHistory(generalRepLadders: [[20, 20, 20]])
        let seed = PartnerPlanResolver.ownerSeedSets(history: habitOnly, defaultReps: 10)
        XCTAssertEqual(seed.map(\.targetReps), [20])
        XCTAssertEqual(seed.map(\.targetWeight), [nil])
    }

    func testOwnerSeedWithNoHistoryAtAllUsesTheEditorDefault() {
        let seed = PartnerPlanResolver.ownerSeedSets(history: .empty, defaultReps: 10,
                                                     defaultSetCount: 3)
        XCTAssertEqual(seed.map(\.targetReps), [10, 10, 10])
    }

    /// A partner who has never done the movement but always works at 20 reps
    /// gets 20, not the owner's prescription (field test 2026-08-19 #3).
    func testPartnerWithoutMovementHistoryUsesTheirHabitualReps() {
        let history = PartnerPlanResolver.ExerciseHistory(
            generalRepLadders: [[20, 20], [20, 20, 20]])
        let sets = PartnerPlanResolver.sets(forOwnerSets: ownerSets([5, 5, 5, 5]),
                                            history: history)
        XCTAssertEqual(sets.map(\.targetReps), [20, 20, 20, 20],
                       "Past the end of their last ladder we use how they usually work")
        XCTAssertEqual(sets.compactMap(\.targetWeight), [], "…but never a made-up load")
    }
}
