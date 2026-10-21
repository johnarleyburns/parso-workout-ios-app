import Foundation
import Testing
@testable import CadenceCore

@Suite struct GeneratedTransitionRestOrderTests {
    private func exercise(_ id: String, _ mechanics: Mechanics) -> SuggestedWorkoutExercise {
        SuggestedWorkoutExercise(candidateID: id, name: id, mechanics: mechanics, plannedSets: 3,
                                 repRange: 8...12, contributions: [], selectionScore: 1)
    }

    private func option(_ exercises: [SuggestedWorkoutExercise],
                        enginePlanID: String? = nil) -> SuggestedWorkoutOption {
        SuggestedWorkoutOption(
            style: .fitness,
            plan: WorkoutPlan(id: "p", name: "P", source: .coachSuggested, scheme: .strength,
                              items: exercises.enumerated().map {
                                  PlanItem(id: $0.offset, movement: $0.element.name, reps: 8, targetSets: 3)
                              }),
            exercises: exercises, initialDeficits: [:], remainingDeficits: [:],
            plannedSetTotal: exercises.count * 3, capTrimmingOccurred: false, citationIDs: [],
            enginePlanID: enginePlanID)
    }

    /// Independent oracle: total transition rest of an order (last unit free).
    private func cost(_ order: [SuggestedWorkoutExercise]) -> Int {
        order.dropLast().reduce(0) { $0 + GeneratedTransitionRestOrder.costSeconds(for: $1.mechanics) }
    }

    private func permutations<T>(_ a: [T]) -> [[T]] {
        guard a.count > 1 else { return [a] }
        return a.indices.flatMap { i -> [[T]] in
            var rest = a; let x = rest.remove(at: i)
            return permutations(rest).map { [x] + $0 }
        }
    }

    @Test func exhaustiveSmallFixturesReachOracleMinimumAndKeepContent() {
        let kinds: [Mechanics] = [.compound, .isolation]
        for n in 2...4 {
            for mask in 0..<(1 << n) {
                let ex = (0..<n).map { exercise("e\($0)", kinds[(mask >> $0) & 1]) }
                let out = GeneratedTransitionRestOrder.apply(to: option(ex))
                let best = permutations(ex).map(cost).min()!
                #expect(cost(out.exercises) == best)
                #expect(Set(out.exercises.map(\.candidateID)) == Set(ex.map(\.candidateID)))
                #expect(out.exercises.count == n)
                #expect(out.plan.items.map(\.movement) == out.exercises.map(\.name))
                #expect(out.plan.items.map(\.id) == Array(0..<n))
                #expect(out.plan.items.allSatisfy { $0.reps == 8 && $0.targetSets == 3 })
                for e in out.exercises { #expect(ex.contains(e)) }
            }
        }
    }

    @Test func tiesKeepOriginalOrderAndIsDeterministic() {
        let ex = [exercise("a", .compound), exercise("b", .compound), exercise("c", .compound)]
        #expect(GeneratedTransitionRestOrder.apply(to: option(ex)).exercises == ex)
        let mixed = [exercise("a", .compound), exercise("b", .isolation), exercise("c", .compound)]
        let once = GeneratedTransitionRestOrder.apply(to: option(mixed))
        #expect(once == GeneratedTransitionRestOrder.apply(to: option(mixed)))
        #expect(GeneratedTransitionRestOrder.apply(to: once) == once)
    }

    @Test func unprovableOptionsKeepOriginalOrder() {
        let ex = [exercise("a", .compound), exercise("b", .isolation)]
        #expect(GeneratedTransitionRestOrder.apply(to: option(ex, enginePlanID: "engine")).exercises == ex)
        let dup = [exercise("a", .compound), exercise("a", .isolation)]
        #expect(GeneratedTransitionRestOrder.apply(to: option(dup)).exercises == dup)
        #expect(GeneratedTransitionRestOrder.apply(to: option([exercise("a", .compound)])).exercises.count == 1)
    }

    @Test func actualSuggestionPipelineAppliesOptimizedOrder() {
        // The generator's own pre-ordering is the unoptimized baseline; the
        // production output must differ from it only by the optimizer's call.
        let candidates = [
            SuggestedExerciseCandidate(id: "squat", name: "Squat", mechanics: .compound,
                                       primaryMuscles: ["quads"], trainingTypes: [.strength]),
            SuggestedExerciseCandidate(id: "curl", name: "Curl", mechanics: .isolation,
                                       primaryMuscles: ["biceps"], trainingTypes: [.strength]),
            SuggestedExerciseCandidate(id: "ext", name: "Leg Extension", mechanics: .isolation,
                                       primaryMuscles: ["quads"], trainingTypes: [.strength]),
        ]
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: [:], candidates: candidates,
            trackedGroups: [.quadriceps, .biceps], preferredSetsPerExercise: 3,
            trainingGoal: .hypertrophy)
        for option in SuggestedWorkoutGenerator.generate(input: input).options where option.exercises.count > 1 {
            let best = permutations(option.exercises).map(cost).min()!
            #expect(cost(option.exercises) == best)
            #expect(option.plan.items.map(\.movement) == option.exercises.map(\.name))
        }
        let personalized = SuggestedWorkoutGenerator.generatePersonalized(input: input)
        if personalized.exercises.count > 1 {
            #expect(cost(personalized.exercises) == permutations(personalized.exercises).map(cost).min()!)
        }
    }
}
