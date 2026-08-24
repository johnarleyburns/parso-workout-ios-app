import XCTest
import CadenceCore
@testable import CadenceFeatures

final class SuggestedWorkoutPresenterTests: XCTestCase {
    private func option(style: SuggestedWorkoutStyle, exercises: [SuggestedWorkoutExercise],
                        remaining: [String: Double] = [:], trimmed: Bool = false) -> SuggestedWorkoutOption {
        SuggestedWorkoutOption(
            style: style,
            plan: WorkoutPlan(id: style.rawValue, name: style.planName, source: .coachSuggested,
                              scheme: .strength, items: exercises.enumerated().map {
                                  PlanItem(id: $0.offset, movement: $0.element.name, reps: 8,
                                           targetSets: $0.element.plannedSets)
                              }),
            exercises: exercises,
            initialDeficits: [:], remainingDeficits: remaining,
            plannedSetTotal: exercises.reduce(0) { $0 + $1.plannedSets },
            capTrimmingOccurred: trimmed, citationIDs: suggestedWorkoutCitationIDs)
    }

    private func exercise(name: String = "Bench Press", sets: Int = 3,
                          inStyle: Bool = true) -> SuggestedWorkoutExercise {
        SuggestedWorkoutExercise(candidateID: name, name: name, mechanics: .compound,
                                 plannedSets: sets, repRange: 8...12, contributions: [],
                                 selectionScore: 3, isInStyle: inStyle)
    }

    func testStateAndExactChoiceOrder() {
        XCTAssertEqual(SuggestedWorkoutState.idle, .idle)
        XCTAssertEqual(SuggestedWorkoutState.calculating, .calculating)
        let diagnostics = SuggestedWorkoutDiagnostics(rawCandidateCount: 1, indexedCandidateCount: 1,
            indexBuildCount: 1, invertedListLookupCount: 1, invertedCandidateVisitCount: 1,
            fullCatalogScanCount: 0, vectorIndexBuildDuration: .zero, allStylesGenerationDuration: .zero)
        let bundle = SuggestedWorkoutBundle(
            options: SuggestedWorkoutStyle.allCases.map { option(style: $0, exercises: [exercise()]) },
            diagnostics: diagnostics)
        XCTAssertEqual(SuggestedWorkoutPresenter.choices(for: bundle).map(\.title),
                       ["Fitness", "Bodyweight", "Powerlifting", "Olympic Weightlifting", "Strongman"])
        XCTAssertEqual(SuggestedWorkoutPresenter.choices(for: bundle).map(\.id),
                       SuggestedWorkoutStyle.allCases)
    }

    func testEmptyPlanIsDisabledAndNamesTheStyle() {
        let empty = SuggestedWorkoutPresenter.choice(
            for: option(style: .strongman, exercises: [], remaining: ["lats": 4]))
        XCTAssertTrue(empty.isDisabled)
        XCTAssertEqual(empty.subtitle,
                       "No available strongman exercises cover this week's gaps.")
        XCTAssertEqual(empty.styleDescription, SuggestedWorkoutStyle.strongman.subtitle)
    }

    func testGapsAndTrimAreDisclosed() {
        let partial = SuggestedWorkoutPresenter.choice(
            for: option(style: .olympic, exercises: [exercise()],
                        remaining: ["lats": 2], trimmed: true))
        XCTAssertTrue(partial.subtitle.contains("Remaining gaps: Lats"))
        XCTAssertTrue(partial.subtitle.contains("Safety cap trimmed"))
    }

    /// A style that borrowed general strength movements has to say so — the user
    /// picked "Olympic" and is entitled to know how much of the plan really is
    /// (NFR-8: the coach discloses, it does not quietly substitute).
    func testStyleShareIsDisclosedWhenTheFallbackWasUsed() {
        let allInStyle = SuggestedWorkoutPresenter.choice(
            for: option(style: .olympic, exercises: [exercise(), exercise(name: "Snatch")]))
        XCTAssertTrue(allInStyle.subtitle.contains("all olympic weightlifting movements"),
                      allInStyle.subtitle)

        let mixed = SuggestedWorkoutPresenter.choice(
            for: option(style: .olympic, exercises: [
                exercise(name: "Snatch"),
                exercise(name: "Cable Curl", inStyle: false),
                exercise(name: "Calf Raise", inStyle: false)
            ]))
        XCTAssertTrue(mixed.subtitle.contains("1 of 3 olympic weightlifting movements"), mixed.subtitle)
        XCTAssertFalse(mixed.isDisabled)
    }

    func testEditablePlanKeepsNameSetsAndReps() {
        let result = SuggestedWorkoutPresenter.editablePlan(
            for: option(style: .bodyweight, exercises: [exercise(sets: 4)]),
            unit: .kilograms, warmupMinutes: 5, cooldownMinutes: 3)
        XCTAssertEqual(result.title, "Bodyweight Plan")
        XCTAssertEqual(result.exercises.first?.sets.count, 4)
        XCTAssertEqual(result.exercises.first?.sets.map { $0.targetReps }, [8, 8, 8, 8])
        XCTAssertEqual(result.warmupMinutes, 5)
        XCTAssertEqual(result.cooldownMinutes, 3)
    }

    func testAboutContractIncludesEveryAlgorithmStepAndResolvableCitations() {
        XCTAssertEqual(SuggestedWorkoutPresenter.citationIDs, suggestedWorkoutCitationIDs)
        XCTAssertEqual(SuggestedWorkoutPresenter.citationIDs.count, 3)
        XCTAssertTrue(SuggestedWorkoutPresenter.citationsResolve)
        XCTAssertEqual(SuggestedWorkoutPresenter.aboutSteps.count, 7)
        let about = SuggestedWorkoutPresenter.aboutSteps.joined(separator: " ")
        XCTAssertTrue(about.contains("\(suggestedWorkoutTargetSetsPerGroup)-set weekly gap"))
        XCTAssertTrue(about.contains("half for one it trains indirectly"))
        XCTAssertTrue(about.contains("not at all for one that only stabilises"))
        XCTAssertTrue(about.contains("\(suggestedWorkoutPlannedSetCap)-set safety cap"))
        XCTAssertTrue(about.contains("Falls back to general strength movements"))
        let code = SuggestedWorkoutPresenter.pseudocode.joined(separator: " ")
        XCTAssertTrue(code.contains("descending muscle mass"))
        XCTAssertTrue(code.contains("compound > isolation"))
        XCTAssertTrue(code.contains("more muscles involved"))
        XCTAssertTrue(code.contains("in-style > out-of-style"))
        XCTAssertFalse(SuggestedWorkoutPresenter.aboutContentContainsRawCitationID,
                      "UI-facing algorithm copy must not expose raw citation IDs")
    }

    /// The chooser copy has to describe the axis the user is actually choosing on.
    func testChooserCopyDescribesStylesNotLengths() {
        XCTAssertTrue(SuggestedWorkoutPresenter.chooserIntro.contains("kind of training"))
        XCTAssertFalse(SuggestedWorkoutPresenter.chooserIntro.lowercased().contains("minimum"))
        XCTAssertTrue(SuggestedWorkoutPresenter.choosingAPlan
            .contains("\(suggestedWorkoutPlannedSetCap)-set safety cap"))
        for style in SuggestedWorkoutStyle.allCases {
            XCTAssertFalse(style.subtitle.isEmpty)
            XCTAssertEqual(style.planName, "\(style.displayName) Plan")
        }
    }

    func testCalculationContractCoversIdleCalculatingReadyFailedAndRetry() async {
        var state: SuggestedWorkoutState = .idle
        XCTAssertEqual(state, .idle)

        state = .calculating
        XCTAssertEqual(state, .calculating)

        let input = SuggestedWorkoutInput(completedSetsByMuscle: [:], candidates: [],
                                          preferredSetsPerExercise: 3, trainingGoal: .strength)
        let bundle = SuggestedWorkoutGenerator.generate(input: input)
        state = .ready(bundle)
        if case .ready(let result) = state {
            XCTAssertEqual(result.options.count, SuggestedWorkoutStyle.allCases.count)
        } else {
            XCTFail("Calculation did not reach ready")
        }

        state = .failed(message: "temporary failure")
        XCTAssertEqual(state, .failed(message: "temporary failure"))
        state = .calculating // Retry returns to the same calculating path.
        XCTAssertEqual(state, .calculating)
    }
}
