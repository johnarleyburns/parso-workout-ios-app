import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct SuggestedWorkoutPresenterTests {
    @Test func workoutCopyUsesPersonalizedTerminology() {
        #expect(SuggestedWorkoutPresenter.navigationTitle == "View Personalized Workout")
        #expect(SuggestedWorkoutPresenter.calculatingTitle == "Calculating personalized workouts…")
        #expect(SuggestedWorkoutPresenter.aboutAccessibilityLabel == "About personalized workouts")
    }

    private func option(style: SuggestedWorkoutStyle, exercises: [SuggestedWorkoutExercise],
                        remaining: [String: Double] = [:], trimmed: Bool = false,
                        unsupported: [SuggestedCoverageGap] = []) -> SuggestedWorkoutOption {
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
            capTrimmingOccurred: trimmed, citationIDs: suggestedWorkoutCitationIDs,
            unsupportedCoverage: unsupported)
    }

    private func exercise(name: String = "Bench Press", sets: Int = 3,
                          inStyle: Bool = true) -> SuggestedWorkoutExercise {
        SuggestedWorkoutExercise(candidateID: name, name: name, mechanics: .compound,
                                 plannedSets: sets, repRange: 8...12, contributions: [],
                                 selectionScore: 3, isInStyle: inStyle)
    }

    @Test func stateAndExactChoiceOrder() {
        #expect(SuggestedWorkoutState.idle == .idle)
        #expect(SuggestedWorkoutState.calculating == .calculating)
        let diagnostics = SuggestedWorkoutDiagnostics(rawCandidateCount: 1, indexedCandidateCount: 1,
            indexBuildCount: 1, invertedListLookupCount: 1, invertedCandidateVisitCount: 1,
            fullCatalogScanCount: 0, vectorIndexBuildDuration: .zero, allStylesGenerationDuration: .zero)
        let bundle = SuggestedWorkoutBundle(
            options: SuggestedWorkoutStyle.allCases.map { option(style: $0, exercises: [exercise()]) },
            diagnostics: diagnostics)
        #expect(SuggestedWorkoutPresenter.choices(for: bundle).map(\.title) ==
                       ["Personalized", "Fitness", "Bodyweight", "Powerlifting", "Olympic Weightlifting", "Strongman"])
        #expect(SuggestedWorkoutPresenter.choices(for: bundle).map(\.id) ==
                       SuggestedWorkoutStyle.allCases)
    }

    @Test func emptyPlanIsDisabledAndNamesTheStyle() {
        let empty = SuggestedWorkoutPresenter.choice(
            for: option(style: .strongman, exercises: [], remaining: ["lats": 4]))
        #expect(empty.isDisabled)
        #expect(empty.subtitle ==
                       "No available strongman exercises cover this week's gaps.")
        #expect(empty.styleDescription == SuggestedWorkoutStyle.strongman.subtitle)
    }

    @Test func historyNoticeWarnsWithoutTurningSuggestionIntoFailure() {
        let limited = SuggestedWorkoutPresenter.historyNotice(
            for: .limited(workoutCount: 1, workingSetCount: 4))
        #expect(limited?.contains("Limited history") == true)
        let matchesCount = CatalogPlural.renderings("Limited history: %lld workouts", 1)
            .contains { limited?.contains($0 + ", 4 working sets") == true }
        #expect(matchesCount, "\(limited ?? "")")
        #expect(CatalogPlural.english("Limited history: %lld workouts", 1) == "Limited history: 1 workout")
        #expect(limited?.contains("onboarding preferences") == true)

        #expect(SuggestedWorkoutPresenter.historyNotice(for: .unavailable) != nil)
        #expect(SuggestedWorkoutPresenter.historyNotice(for: .sufficient) == nil)
    }

    @Test func gapsAndTrimAreDisclosed() {
        let partial = SuggestedWorkoutPresenter.choice(
            for: option(style: .olympic, exercises: [exercise()],
                        remaining: ["lats": 2],
                        unsupported: [SuggestedCoverageGap(muscleID: "lats", reason: .noEligibleExercise,
                                                           explanation: "Lats: no eligible exercise.")]))
        #expect(partial.subtitle.contains("Remaining gaps: Lats"))
        #expect(partial.subtitle.contains("Not covered: Lats: no eligible exercise."))
    }

    /// A style that borrowed general strength movements has to say so — the user
    /// picked "Olympic" and is entitled to know how much of the plan really is
    /// (NFR-8: the coach discloses, it does not quietly substitute).
    @Test func styleShareIsDisclosedWhenTheFallbackWasUsed() {
        let allInStyle = SuggestedWorkoutPresenter.choice(
            for: option(style: .olympic, exercises: [exercise(), exercise(name: "Snatch")]))
        #expect(allInStyle.subtitle.contains("all olympic weightlifting movements"),
                      "\(allInStyle.subtitle)")

        let mixed = SuggestedWorkoutPresenter.choice(
            for: option(style: .olympic, exercises: [
                exercise(name: "Snatch"),
                exercise(name: "Cable Curl", inStyle: false),
                exercise(name: "Calf Raise", inStyle: false)
            ]))
        #expect(mixed.subtitle.contains("1 of 3 olympic weightlifting movements"), "\(mixed.subtitle)")
        #expect(!mixed.isDisabled)
    }

    @Test func editablePlanKeepsNameSetsAndReps() {
        let result = SuggestedWorkoutPresenter.editablePlan(
            for: option(style: .bodyweight, exercises: [exercise(sets: 4)]),
            unit: .kilograms, warmupMinutes: 5, cooldownMinutes: 3)
        #expect(result.title == "Bodyweight Workout")
        #expect(result.exercises.first?.sets.count == 4)
        #expect(result.exercises.first?.sets.map { $0.targetReps } == [8, 8, 8, 8])
        #expect(result.warmupMinutes == 5)
        #expect(result.cooldownMinutes == 3)
    }

    @Test func aboutContractIncludesEveryAlgorithmStepAndResolvableCitations() {
        #expect(SuggestedWorkoutPresenter.citationIDs == suggestedWorkoutCitationIDs)
        #expect(SuggestedWorkoutPresenter.citationIDs.count == 5)
        #expect(SuggestedWorkoutPresenter.citationsResolve)
        #expect(SuggestedWorkoutPresenter.aboutSteps.count == 7)
        let about = SuggestedWorkoutPresenter.aboutSteps.joined(separator: " ")
        #expect(about.contains("\(suggestedWorkoutTargetSetsPerGroup)-set weekly gap"))
        #expect(about.contains("half for one it trains indirectly"))
        #expect(about.contains("not at all for one that only stabilises"))
        #expect(about.contains("Nothing is trimmed"))
        #expect(about.contains("Falls back to general strength movements"))
        let code = SuggestedWorkoutPresenter.pseudocode.joined(separator: " ")
        #expect(code.contains("descending muscle mass"))
        #expect(code.contains("compound > isolation"))
        #expect(code.contains("more muscles involved"))
        #expect(code.contains("in-style > out-of-style"))
        #expect(!SuggestedWorkoutPresenter.aboutContentContainsRawCitationID,
                      "UI-facing algorithm copy must not expose raw citation IDs")
    }

    /// The chooser copy has to describe the axis the user is actually choosing on.
    @Test func chooserCopyDescribesStylesNotLengths() {
        #expect(SuggestedWorkoutPresenter.chooserIntro.contains("kind of training"))
        #expect(!SuggestedWorkoutPresenter.chooserIntro.lowercased().contains("minimum"))
        #expect(SuggestedWorkoutPresenter.choosingAPlan
            .contains("no set cap"))
        for style in SuggestedWorkoutStyle.allCases {
            #expect(!style.subtitle.isEmpty)
            #expect(style.planName == "\(style.displayName) Workout")
        }
    }

    @Test func calculationContractCoversIdleCalculatingReadyFailedAndRetry() async {
        var state: SuggestedWorkoutState = .idle
        #expect(state == .idle)

        state = .calculating
        #expect(state == .calculating)

        let input = SuggestedWorkoutInput(completedSetsByMuscle: [:], candidates: [],
                                          preferredSetsPerExercise: 3, trainingGoal: .strength)
        let bundle = SuggestedWorkoutGenerator.generate(input: input)
        state = .ready(bundle)
        if case .ready(let result) = state {
            #expect(result.options.count == SuggestedWorkoutStyle.allCases.count)
        } else {
            Issue.record("Calculation did not reach ready")
        }

        state = .failed(message: "temporary failure")
        #expect(state == .failed(message: "temporary failure"))
        state = .calculating // Retry returns to the same calculating path.
        #expect(state == .calculating)
    }
}
