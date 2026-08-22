import XCTest
import CadenceCore
@testable import CadenceFeatures

final class SuggestedWorkoutPresenterTests: XCTestCase {
    private func option(tier: SuggestedWorkoutTier, exercises: [SuggestedWorkoutExercise],
                        remaining: [String: Double] = [:], trimmed: Bool = false) -> SuggestedWorkoutOption {
        SuggestedWorkoutOption(
            tier: tier,
            plan: WorkoutPlan(id: tier.rawValue, name: tier.planName, source: .coachSuggested,
                              scheme: .strength, items: exercises.enumerated().map {
                                  PlanItem(id: $0.offset, movement: $0.element.name, reps: 8,
                                           targetSets: $0.element.plannedSets)
                              }),
            exercises: exercises,
            initialDeficits: [:], remainingDeficits: remaining,
            plannedSetTotal: exercises.reduce(0) { $0 + $1.plannedSets },
            capTrimmingOccurred: trimmed, citationIDs: suggestedWorkoutCitationIDs)
    }

    private func exercise(name: String = "Bench Press", sets: Int = 3) -> SuggestedWorkoutExercise {
        SuggestedWorkoutExercise(candidateID: name, name: name, mechanics: .compound,
                                 plannedSets: sets, repRange: 8...12, contributions: [], selectionScore: 3)
    }

    func testStateAndExactChoiceOrder() {
        XCTAssertEqual(SuggestedWorkoutState.idle, .idle)
        XCTAssertEqual(SuggestedWorkoutState.calculating, .calculating)
        let diagnostics = SuggestedWorkoutDiagnostics(rawCandidateCount: 1, indexedCandidateCount: 1,
            indexBuildCount: 1, invertedListLookupCount: 1, invertedCandidateVisitCount: 1,
            fullCatalogScanCount: 0, vectorIndexBuildDuration: .zero, threeTierGenerationDuration: .zero)
        let bundle = SuggestedWorkoutBundle(options: [
            option(tier: .minimum, exercises: [exercise()]),
            option(tier: .medium, exercises: [exercise()]),
            option(tier: .maximal, exercises: [exercise()])
        ], diagnostics: diagnostics)
        XCTAssertEqual(SuggestedWorkoutPresenter.choices(for: bundle).map(\.title),
                       ["Minimum Workout", "Medium Workout", "Maximal Workout"])
    }

    func testEmptyPlanIsDisabledAndGapsAndTrimAreDisclosed() {
        let empty = SuggestedWorkoutPresenter.choice(for: option(tier: .minimum, exercises: [], remaining: ["lats": 4]))
        XCTAssertTrue(empty.isDisabled)
        XCTAssertEqual(empty.subtitle, "No available exercises cover the remaining muscle-group gaps.")
        let partial = SuggestedWorkoutPresenter.choice(for: option(tier: .maximal, exercises: [exercise()],
                                                                     remaining: ["lats": 2], trimmed: true))
        XCTAssertTrue(partial.subtitle.contains("Remaining gaps: Lats"))
        XCTAssertTrue(partial.subtitle.contains("Safety cap trimmed"))
    }

    func testEditablePlanKeepsNameSetsAndReps() {
        let result = SuggestedWorkoutPresenter.editablePlan(
            for: option(tier: .medium, exercises: [exercise(sets: 4)]),
            unit: .kilograms, warmupMinutes: 5, cooldownMinutes: 3)
        XCTAssertEqual(result.title, "Medium Plan")
        XCTAssertEqual(result.exercises.first?.sets.count, 4)
        XCTAssertEqual(result.exercises.first?.sets.map { $0.targetReps }, [8, 8, 8, 8])
        XCTAssertEqual(result.warmupMinutes, 5)
        XCTAssertEqual(result.cooldownMinutes, 3)
    }

    func testAboutContractIncludesEveryAlgorithmStepAndResolvableCitations() {
        XCTAssertEqual(SuggestedWorkoutPresenter.citationIDs, suggestedWorkoutCitationIDs)
        XCTAssertEqual(SuggestedWorkoutPresenter.citationIDs.count, 2)
        XCTAssertTrue(SuggestedWorkoutPresenter.citationsResolve)
        XCTAssertEqual(SuggestedWorkoutPresenter.aboutSteps.count, 6)
        XCTAssertTrue(SuggestedWorkoutPresenter.aboutSteps.joined(separator: " ").contains("4, 8, and 12"))
        XCTAssertTrue(SuggestedWorkoutPresenter.aboutSteps.joined(separator: " ").contains("half credit"))
        XCTAssertTrue(SuggestedWorkoutPresenter.aboutSteps.joined(separator: " ").contains("20, 30, or 40"))
        XCTAssertTrue(SuggestedWorkoutPresenter.pseudocode.joined(separator: " ").contains("descending muscle mass"))
        XCTAssertTrue(SuggestedWorkoutPresenter.pseudocode.joined(separator: " ").contains("compound > isolation"))
        XCTAssertTrue(SuggestedWorkoutPresenter.pseudocode.joined(separator: " ").contains("more muscles involved"))
    }
}
