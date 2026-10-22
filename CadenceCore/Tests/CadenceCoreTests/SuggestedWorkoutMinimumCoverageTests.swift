import XCTest
@testable import CadenceCore

/// Proves the defined objective only: the fewest exercises that touch every
/// coverable required group at least once. Not a physiological-optimality claim.
final class SuggestedWorkoutMinimumCoverageTests: XCTestCase {
    private struct RNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 11 ^ state << 7
        }
    }

    /// Independent oracle: enumerate every subset by size.
    private func oracleMinimum(_ masks: [UInt32], required: UInt32) -> Int {
        let reachable = masks.reduce(0, |) & required
        if reachable == 0 { return 0 }
        var best = Int.max
        for subset in 0..<(1 << masks.count) {
            var union = UInt32(0)
            for i in masks.indices where subset >> i & 1 == 1 { union |= masks[i] }
            if union & reachable == reachable { best = min(best, subset.nonzeroBitCount) }
        }
        return best
    }

    func testSolverMatchesExhaustiveOracleOnGeneratedMatrices() {
        var rng = RNG(state: 303)
        for _ in 0..<300 {
            let groups = Int.random(in: 1...8, using: &rng)
            let count = Int.random(in: 1...10, using: &rng)
            let masks = (0..<count).map { _ in UInt32.random(in: 0..<(1 << UInt32(groups)), using: &rng) }
            let required = UInt32((1 << groups) - 1)
            let picks = SuggestedWorkoutGenerator.minimumCoverIndices(masks: masks, required: required)
            XCTAssertEqual(picks.count, oracleMinimum(masks, required: required), "\(masks)")
            XCTAssertEqual(Set(picks).count, picks.count)
            let union = picks.reduce(UInt32(0)) { $0 | masks[$1] }
            XCTAssertEqual(union & masks.reduce(0, |), masks.reduce(0, |) & required)
        }
    }

    func testGreedyCounterexampleUsesTwoExercisesNotThree() {
        // Greedy takes the broad exercise first and needs three; two suffice.
        let candidates = [
            c("wide", "A Wide", ["chest", "lats", "quadriceps"]),
            c("left", "B Left", ["chest", "lats", "hamstrings"].filter { $0 != "lats" } + ["biceps"]),
            c("right", "C Right", ["lats", "quadriceps", "hamstrings", "biceps"].filter { $0 != "biceps" }),
        ]
        let option = generate(candidates, tracked: [.chest, .lats, .quadriceps, .hamstrings, .biceps])
            .option(.fitness)
        let ids = Set(option.exercises.map(\.candidateID))
        XCTAssertEqual(option.exercises.count, 2, "\(ids)")
        XCTAssertTrue(option.unsupportedCoverage.isEmpty)
    }

    func testProductionMatchesOracleOnRandomFixtures() {
        var rng = RNG(state: 77)
        let groups: [MuscleGroup] = [.chest, .lats, .quadriceps, .hamstrings, .biceps, .triceps]
        for round in 0..<60 {
            let candidates = (0..<Int.random(in: 1...9, using: &rng)).map { i in
                let muscles = groups.filter { _ in Bool.random(using: &rng) }
                return c("r\(round)-\(i)", "Ex \(i)", muscles.map(\.rawValue))
            }
            let option = generate(candidates, tracked: Set(groups)).option(.fitness)
            let masks = candidates.map { cand in
                groups.indices.reduce(UInt32(0)) {
                    cand.primaryMuscles.contains(groups[$1].rawValue) ? $0 | 1 << UInt32($1) : $0
                }
            }
            let required = UInt32((1 << groups.count) - 1)
            let expected = oracleMinimum(masks, required: required)
            // Candidates with no tracked muscle never enter the plan; a plan with
            // nothing coverable falls back to one maintenance movement.
            XCTAssertEqual(option.exercises.count, max(expected, expected == 0 ? 1 : 0), "round \(round)")
            XCTAssertFalse(option.capTrimmingOccurred)
            XCTAssertEqual(option.plannedSetTotal, option.exercises.count * 3)
        }
    }

    func testDuplicateMappingsTieBreakDeterministicallyAndUnsatisfiedGroupsAreExplained() {
        let candidates = [
            c("b", "Same", ["chest"]), c("a", "Same", ["chest"]), c("z", "Zed", ["chest"]),
        ]
        let first = generate(candidates, tracked: [.chest, .lats]).option(.fitness)
        let second = generate(candidates.reversed(), tracked: [.chest, .lats]).option(.fitness)
        XCTAssertEqual(first.exercises.map(\.candidateID), second.exercises.map(\.candidateID))
        XCTAssertEqual(first.exercises.count, 1)
        XCTAssertEqual(first.unsupportedCoverage.map(\.muscleID), ["lats"])
        XCTAssertTrue(first.rationale?.whyWorkout.contains("Not covered: ") == true)
    }

    func testGoalDefaultsAndHistorySetsApplyAfterSelectionWithoutCap() {
        let groups = MuscleGroup.allCases
        let candidates = groups.enumerated().map { c("g\($0.offset)", "Ex \($0.offset)", [$0.element.rawValue]) }
        for (goal, reps) in [(TrainingGoal.strength, 3), (.hypertrophy, 8), (.endurance, 20)] {
            let option = generate(candidates, goal: goal).option(.fitness)
            XCTAssertTrue(option.exercises.allSatisfy { $0.repRange == reps...reps && $0.plannedSets == 3 })
            XCTAssertEqual(option.plannedSetTotal, option.exercises.count * 3)
            XCTAssertGreaterThan(option.plannedSetTotal, 20)
            XCTAssertFalse(option.capTrimmingOccurred)
        }
        let withHistory = generate(candidates, sets: 5, historyWorkoutCount: 4).option(.fitness)
        XCTAssertTrue(withHistory.exercises.allSatisfy { $0.plannedSets == 5 })
        XCTAssertEqual(withHistory.plan.items.count, withHistory.exercises.count)
        XCTAssertEqual(withHistory.plan.items.map(\.targetSets), withHistory.exercises.map(\.plannedSets))
    }

    private func c(_ id: String, _ name: String, _ primary: [String]) -> SuggestedExerciseCandidate {
        SuggestedExerciseCandidate(id: id, name: name, mechanics: .compound,
                                   primaryMuscles: primary, secondaryMuscles: [])
    }

    private func generate(_ candidates: [SuggestedExerciseCandidate],
                          tracked: Set<MuscleGroup> = MuscleGroup.defaultTracked,
                          goal: TrainingGoal = .hypertrophy, sets: Int? = nil,
                          historyWorkoutCount: Int = 0) -> SuggestedWorkoutBundle {
        SuggestedWorkoutGenerator.generate(input: SuggestedWorkoutInput(
            completedSetsByMuscle: [:], candidates: candidates,
            historyWorkoutCount: historyWorkoutCount, trackedGroups: tracked,
            preferredSetsPerExercise: 4, mostRecentExerciseWorkingSets: sets,
            trainingGoal: goal))
    }
}
