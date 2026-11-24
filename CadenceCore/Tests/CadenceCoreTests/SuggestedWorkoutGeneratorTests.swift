#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

/// The generator after the DB++ adoption (decision D6): one 4-set-per-group
/// target, six training styles, and a fallback pass that keeps a style from
/// silently abandoning a muscle it cannot reach.
struct SuggestedWorkoutGeneratorTests {

    // MARK: - Target and style shape

    @Test func everyStyleSolvesTheSameMinimumTarget() {
        let bundle = generate(completed: [:], candidates: [])

        #expect(bundle.options.map(\.style) == SuggestedWorkoutStyle.allCases)
        #expect(bundle.options.count == SuggestedWorkoutStyle.allCases.count)
        for option in bundle.options where option.style != .personalized {
            #expect(option.initialDeficits.count == MuscleGroup.defaultTracked.count)
            #expect(option.initialDeficits.values.allSatisfy { $0 == 4 })
            #expect(option.remainingDeficits == option.initialDeficits)
            #expect(!option.isLaunchable)
        }
    }

    @Test func limitedHistoryDoesNotBlockPreferenceBasedSuggestion() {
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: [:],
            candidates: [candidate("chest", "Bench Press", primary: ["chest"])],
            historyWorkoutCount: 1,
            historyWorkingSetCount: 4,
            trackedGroups: [.chest],
            preferredSetsPerExercise: 4,
            trainingGoal: .hypertrophy)

        let bundle = SuggestedWorkoutGenerator.generate(input: input)

        #expect(bundle.historyQuality == .limited(workoutCount: 1, workingSetCount: 4))
        #expect(bundle.option(.fitness).isLaunchable,
                      "limited history must warn without blocking generation")
    }

    @Test func historyAwareIntentRequestsHistoryWhenSnapshotExists() {
        let intent = TrainingEngineBridge.workoutIntent(
            goal: .hypertrophy,
            environment: "commercial_gym",
            schedule: .default,
            useHistory: true,
            historyWindow: "last_28_days")

        #expect(intent.useHistory == true)
        #expect(intent.historyWindow == "last_28_days")
    }

    /// Only tracked groups get a deficit — otherwise the solver spends slots on
    /// groups the catalog does not target by default (decision D4).
    @Test func untrackedGroupsGetNoDeficit() {
        let bundle = generate(completed: [:], candidates: [], tracked: [.chest, .lats])

        #expect(bundle.option(.fitness).initialDeficits == ["chest": 4, "lats": 4])
        #expect(bundle.option(.fitness).initialDeficits["tibialis"] == nil)
    }

    @Test func completedMusclesNormalizeMergeAndIgnoreUnknownValues() {
        let bundle = generate(
            completed: [" Lats ": 1.5, "lats": 2.0, "LATS\n": 0.5,
                        "unknown": 99, "  ": 99],
            candidates: []
        )

        #expect(bundle.option(.fitness).initialDeficits["lats"] == 0)
        #expect(bundle.option(.fitness).initialDeficits["unknown"] == nil)
    }

    @Test func singleExercisePrioritizesSelectedMuscleThenCoversOtherGaps() {
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: ["chest": 3],
            candidates: [
                candidate("chest-only", "Chest Fly", mechanics: .isolation, primary: ["chest"]),
                candidate("chest-shoulder", "Chest Shoulder Press",
                          primary: ["chest", "shoulders"]),
                candidate("shoulder-triceps", "Shoulder Triceps Press",
                          primary: ["shoulders", "triceps"])
            ],
            trackedGroups: [.chest, .shoulders, .triceps],
            preferredSetsPerExercise: 4,
            trainingGoal: .hypertrophy)

        let suggestion = SuggestedWorkoutGenerator.suggestSingleExercise(
            input: input,
            style: .fitness,
            priorityMuscle: .chest)

        #expect(suggestion?.name == "Chest Shoulder Press")
        #expect(suggestion?.contributions.map(\.muscleID) == ["chest", "shoulders"])
    }

    // MARK: - Regenerating after excluding an exercise

    /// Real user report: excluding an exercise from a suggested workout left
    /// it sitting right there in the plan, because the exclusion only
    /// changed *future* suggestion runs. `excluding(candidateID:)` +
    /// `generate` must recompute the plan from scratch without that
    /// candidate at all, not just remove it from the existing plan (which
    /// could leave a gap the solver would otherwise have filled with a
    /// substitute).
    @Test func excludingACandidateAndRegeneratingReplacesItWithASubstitute() {
        let excluded = candidate("chest-bench", "Bench Press", primary: ["chest"])
        let substitute = candidate("chest-fly", "Cable Fly", mechanics: .isolation, primary: ["chest"])
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: [:],
            candidates: [excluded, substitute],
            trackedGroups: [.chest],
            preferredSetsPerExercise: 4,
            trainingGoal: .hypertrophy)

        let original = SuggestedWorkoutGenerator.generate(input: input)
        #expect(original.option(.fitness).exercises.contains { $0.name == "Bench Press" })

        let regenerated = SuggestedWorkoutGenerator.generate(
            input: input.excluding(candidateID: "chest-bench"))

        #expect(
            !regenerated.option(.fitness).exercises.contains { $0.name == "Bench Press" },
            "the excluded exercise must never reappear in a from-scratch regeneration")
        #expect(
            regenerated.option(.fitness).exercises.contains { $0.name == "Cable Fly" },
            "the solver must fill the same gap with the remaining candidate, not leave it open")
    }

    /// Excluding a candidate that is not in the pool at all (already
    /// excluded, or never matched) is a safe no-op — the regenerated input
    /// is equal to the original.
    @Test func excludingAnUnknownCandidateIDIsANoOp() {
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: [:],
            candidates: [candidate("chest-bench", "Bench Press", primary: ["chest"])],
            trackedGroups: [.chest],
            preferredSetsPerExercise: 4,
            trainingGoal: .hypertrophy)

        #expect(input.excluding(candidateID: "not-present") == input)
    }

    // MARK: - Greedy selection

    @Test func largestDeficitIsSelectedFirst() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 2
        let chest = candidate("chest", "Zulu Chest", primary: ["chest"])
        let lats = candidate("lats", "Alpha Lats", primary: ["lats"])

        let option = generate(completed: completed, candidates: [lats, chest]).option(.fitness)

        #expect(option.exercises.map(\.candidateID) == ["chest", "lats"])
    }

    @Test func multiDeficitExerciseWinsByExactCappedScore() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let single = candidate("single", "Single", primary: ["chest"])
        let combo = candidate("combo", "Combo", primary: ["chest", "lats"])

        let option = generate(completed: completed, candidates: [single, combo]).option(.fitness)

        #expect(option.exercises.first?.candidateID == "combo")
        #expect(abs((option.exercises.first?.selectionScore ?? .nan) - 6) <= 1e-12)
    }

    @Test func directAndIndirectContributionsUpdateDeficitsAndPrimaryWins() throws {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let mixed = candidate(
            "mixed", "Mixed", primary: [" chest "],
            secondary: ["CHEST", " lats ", "unknown", "  "]
        )

        let option = generate(completed: completed, candidates: [mixed]).option(.fitness)
        let exercise = try #require(option.exercises.first)

        #expect(abs(exercise.selectionScore - 4.5) <= 1e-12)
        // Contributions are emitted in dimension order, which is
        // MuscleGroup.canonicalOrder — descending muscle mass — so lats precedes chest.
        #expect(exercise.contributions.map(\.muscleID) == ["lats", "chest"])
        #expect(exercise.contributions.map(\.weight) == [VolumeCredit.indirect, VolumeCredit.direct])
        #expect(abs((option.remainingDeficits["chest"] ?? .nan) - 1) <= 1e-12)
        #expect(abs((option.remainingDeficits["lats"] ?? .nan) - 2.5) <= 1e-12)
    }

    @Test func scoreCapsCreditAndIgnoresSatisfiedMuscles() {
        var completed = satisfied(at: 4)
        completed["chest"] = 3
        let exercise = candidate("combo", "Combo", primary: ["chest", "lats"])

        let option = generate(completed: completed, candidates: [exercise]).option(.fitness)

        #expect(abs((option.exercises.first?.selectionScore ?? .nan) - 1) <= 1e-12)
        #expect(abs((option.remainingDeficits["chest"] ?? .nan) - 0) <= 1e-12)
        #expect(abs((option.remainingDeficits["lats"] ?? .nan) - 0) <= 1e-12)
    }

    @Test func preferredSetValuesChangePlannedSetsScoresAndContributions() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let combo = candidate("combo", "Combo", primary: ["chest", "lats"])

        let three = generate(completed: completed, candidates: [combo], sets: 3).option(.fitness)
        let four = generate(completed: completed, candidates: [combo], sets: 4).option(.fitness)

        #expect(three.exercises.first?.plannedSets == 3)
        #expect(abs((three.exercises.first?.selectionScore ?? .nan) - 6) <= 1e-12)
        #expect(four.exercises.first?.plannedSets == 4)
        #expect(abs((four.exercises.first?.selectionScore ?? .nan) - 8) <= 1e-12)
        #expect(four.exercises.first?.contributions.map(\.plannedSetContribution) == [4, 4])
    }

    @Test func selectedExerciseNeverDuplicatesAndUnresolvedDeficitTerminates() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let chest = candidate("only", "Only Chest", primary: ["chest"])

        let option = generate(completed: completed, candidates: [chest]).option(.fitness)

        #expect(option.exercises.map(\.candidateID) == ["only"])
        #expect(abs((option.remainingDeficits["chest"] ?? .nan) - 1) <= 1e-12)
        #expect(abs((option.remainingDeficits["lats"] ?? .nan) - 4) <= 1e-12)
        #expect(option.unresolvedDeficits["chest"] == 1)
        #expect(option.unresolvedDeficits["lats"] == 4)
    }

    @Test func equalDeficitsPrioritizeLargerMusclesBeforeCatalogOrder() {
        var completed = satisfied(at: 4)
        completed["biceps"] = 0
        completed["quadriceps"] = 0
        let biceps = candidate("biceps", "Alpha Biceps", primary: ["biceps"])
        let quads = candidate("quads", "Zulu Quads", primary: ["quadriceps"])

        let option = generate(completed: completed, candidates: [biceps, quads]).option(.fitness)

        #expect(option.exercises.map(\.candidateID) == ["quads", "biceps"])
        #expect(MuscleGroup.massPriority(for: .quadriceps) < MuscleGroup.massPriority(for: .biceps))
    }

    @Test func sameMuscleEqualScorePrefersCompoundBeforeOtherTieBreaks() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let isolation = candidate("isolation", "Alpha", mechanics: .isolation, primary: ["chest"])
        let compound = candidate("compound", "Zulu", primary: ["chest"])

        let option = generate(completed: completed, candidates: [isolation, compound]).option(.fitness)

        #expect(option.exercises.first?.selectionScore == 3)
        #expect(option.exercises.first?.candidateID == "compound")
    }

    @Test func sameMuscleAndMechanicsPrefersBroaderMuscleInvolvementEvenWhenSatisfied() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let narrow = candidate("narrow", "Alpha", primary: ["chest"])
        let broad = candidate("broad", "Zulu", primary: ["chest"], secondary: ["biceps"])

        let option = generate(completed: completed, candidates: [narrow, broad]).option(.fitness)

        #expect(option.exercises.first?.selectionScore == 3)
        #expect(option.exercises.first?.candidateID == "broad")
    }

    @Test func tieBreakPrefersCompoundThenLocalizedName() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let isolation = candidate("isolation", "Alpha", mechanics: .isolation, primary: ["chest"])
        let compound = candidate("compound", "Zulu", primary: ["chest"])
        #expect(
            generate(completed: completed, candidates: [isolation, compound]).option(.fitness)
                .exercises.first?.candidateID
            == "compound"
        )

        let alpha = candidate("alpha", "Alpha", primary: ["chest"])
        let zulu = candidate("zulu", "Zulu", primary: ["chest"])
        #expect(
            generate(completed: completed, candidates: [zulu, alpha]).option(.fitness)
                .exercises.first?.candidateID
            == "alpha"
        )
    }

    @Test func caseInsensitiveDuplicateNamesMergeWithStableIDTieBreak() throws {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let laterID = candidate("z-id", " Press ", primary: ["chest"])
        let earlierID = candidate("a-id", "press", secondary: ["lats"])

        let option = generate(completed: completed, candidates: [laterID, earlierID]).option(.fitness)
        let exercise = try #require(option.exercises.first)

        #expect(exercise.candidateID == "a-id")
        #expect(exercise.name == "press")
        #expect(exercise.contributions.map(\.muscleID) == ["lats", "chest"])
        #expect(option.exercises.count == 1)
    }

    // MARK: - Volume eligibility

    /// Stretching, plyometrics and cardio can never be prescribed as strength
    /// work, whatever muscles they list (decision D3).
    @Test func volumeIneligibleMovementsAreNeverSuggested() {
        var completed = satisfied(at: 4)
        completed["hamstrings"] = 0
        let stretch = SuggestedExerciseCandidate(
            id: "stretch", name: "Standing Hamstring Stretch", mechanics: .isolation,
            primaryMuscles: ["hamstrings"], secondaryMuscles: [],
            volumeEligible: false, trainingTypes: [.stretching])

        let bundle = generate(completed: completed, candidates: [stretch])

        for option in bundle.options where option.style != .personalized {
            #expect(option.exercises.isEmpty, "\(option.style) suggested a stretch")
            #expect(option.remainingDeficits["hamstrings"] == 4)
        }
    }

    @Test func nonResistanceClassificationIsNeverSuggestedEvenIfMarkedVolumeEligible() {
        var completed = satisfied(at: 4)
        completed["hamstrings"] = 0
        let catStretch = SuggestedExerciseCandidate(
            id: "cat-stretch", name: "Cat Stretch", mechanics: .isolation,
            primaryMuscles: ["hamstrings"], volumeEligible: true,
            trainingTypes: [.stretching])
        let mobility = SuggestedExerciseCandidate(
            id: "mobility", name: "Hip Mobility", mechanics: .isolation,
            primaryMuscles: ["hamstrings"], volumeEligible: true,
            trainingTypes: [.mobility])
        let cardio = SuggestedExerciseCandidate(
            id: "cardio", name: "Leg Cardio", mechanics: .compound,
            primaryMuscles: ["hamstrings"], volumeEligible: true,
            trainingTypes: [.cardio])
        let unclassified = SuggestedExerciseCandidate(
            id: "unclassified", name: "Unclassified Movement", mechanics: .compound,
            primaryMuscles: ["hamstrings"], volumeEligible: true,
            trainingTypes: [])

        let bundle = generate(completed: completed,
                              candidates: [catStretch, mobility, cardio, unclassified])

        for option in bundle.options {
            #expect(!option.exercises.contains { exercise in
                ["Cat Stretch", "Hip Mobility", "Leg Cardio", "Unclassified Movement"].contains(exercise.name)
            }, "\(option.style) suggested a non-resistance movement")
        }
    }

    @Test func everyLaunchableSuggestionCarriesWorkoutAndExerciseReasons() {
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: ["chest": 0],
            candidates: [candidate("bench", "Bench Press", primary: ["chest"])],
            trackedGroups: [.chest],
            preferredSetsPerExercise: 3,
            trainingGoal: .strength)

        let bundle = SuggestedWorkoutGenerator.generate(input: input)
        for option in bundle.options where option.isLaunchable {
            guard let rationale = option.rationale else {
                Issue.record("Launchable \(option.style) option must carry rationale")
                continue
            }
            #expect(!rationale.whyWorkout.isEmpty)
            #expect(rationale.exercises.map(\.exerciseName) ==
                           option.exercises.map(\.name))
            #expect(rationale.exercises.allSatisfy {
                !$0.whyExercise.isEmpty && !$0.whySetRep.isEmpty
            })
        }
    }

    // MARK: - Styles

    @Test func eachStylePrefersItsOwnMovementsForTheSameGap() {
        var completed = satisfied(at: 4)
        completed["quadriceps"] = 0
        let general = styled("general", "Leg Press", ["quadriceps"], types: [.strength])
        let oly = styled("oly", "Power Clean", ["quadriceps"], types: [.strength, .olympicWeightlifting])
        let strong = styled("strong", "Yoke Walk", ["quadriceps"], types: [.strength, .strongman])
        let power = styled("power", "Low-Bar Squat", ["quadriceps"], types: [.strength, .powerlifting])
        let body = styled("body", "Pistol Squat", ["quadriceps"], types: [.strength],
                          modalities: [.bodyweight])
        let pool = [general, oly, strong, power, body]

        let bundle = generate(completed: completed, candidates: pool)

        #expect(bundle.option(.olympic).exercises.first?.candidateID == "oly")
        #expect(bundle.option(.strongman).exercises.first?.candidateID == "strong")
        #expect(bundle.option(.powerlifting).exercises.first?.candidateID == "power")
        #expect(bundle.option(.bodyweight).exercises.first?.candidateID == "body")
        #expect(bundle.option(.fitness).exercises.first?.candidateID == "general")
        // A 4-set gap and 3 sets per exercise leaves a remainder, so each plan
        // takes a second movement too — but the style's own is always picked first.
        for option in bundle.options where option.style != .personalized {
            #expect(option.exercises.first?.isInStyle == true, "\(option.style)")
        }
    }

    @Test func bodyweightNeverBorrowsAnExternalLoadWhenItsPoolExists() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let bodyweight = styled("body", "Push-Up", ["chest"], types: [.strength],
                               modalities: [.bodyweight])
        let barbell = styled("barbell", "Clean and Jerk", ["chest"], types: [.strength])

        let option = generate(completed: completed, candidates: [barbell, bodyweight]).option(.bodyweight)

        #expect(option.exercises.map(\.candidateID) == ["body"])
        #expect(option.exercises.allSatisfy { $0.isInStyle })
        #expect(!option.exercises.contains { $0.name.localizedCaseInsensitiveContains("clean and jerk") })
    }

    @Test func explicitExternalEquipmentOverridesAStaleBodyweightModalityTag() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let staleClean = SuggestedExerciseCandidate(
            id: "stale-clean", name: "Clean and Jerk", mechanics: .compound,
            primaryMuscles: ["chest"], equipment: .barbell,
            trainingTypes: [.strength], modalities: [.bodyweight])
        let pushUp = SuggestedExerciseCandidate(
            id: "push-up", name: "Push-Up", mechanics: .compound,
            primaryMuscles: ["chest"], equipment: .bodyweight,
            trainingTypes: [.strength], modalities: [.bodyweight])

        let option = generate(completed: completed, candidates: [staleClean, pushUp])
            .option(.bodyweight)

        #expect(option.exercises.first?.candidateID == "push-up")
        #expect(!option.exercises.contains { $0.name == "Clean and Jerk" })
    }

    /// NFR-8: a style narrows the movements, it does not abandon a muscle. When
    /// the style pool cannot reach a gap, the second pass fills it from the whole
    /// catalog and the option reports how much it borrowed.
    @Test func styleFallsBackToGeneralMovementsForGapsItCannotReach() throws {
        var completed = satisfied(at: 4)
        completed["quadriceps"] = 0
        completed["biceps"] = 0
        let oly = styled("oly", "Snatch", ["quadriceps"], types: [.strength, .olympicWeightlifting])
        let curl = styled("curl", "Cable Curl", ["biceps"], types: [.strength],
                          mechanics: .isolation)

        let option = generate(completed: completed, candidates: [oly, curl]).option(.olympic)

        // Selection order is oly, curl; the transition-rest ordering then ends
        // the session on the longer-transition compound movement.
        #expect(option.exercises.map(\.candidateID) == ["curl", "oly"])
        #expect(option.exercises.map(\.isInStyle) == [false, true])
        #expect(option.inStyleExerciseCount == 1)
        #expect(abs((option.remainingDeficits["biceps"] ?? .nan) - 1) <= 1e-12)
    }

    /// The fallback runs second, so the style's own movement wins a gap even when
    /// a general movement scores identically.
    @Test func inStyleMovementWinsAnExactTieAgainstTheFallback() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let general = styled("general", "Alpha Press", ["chest"], types: [.strength])
        let strong = styled("strong", "Zulu Log Press", ["chest"], types: [.strength, .strongman])

        let option = generate(completed: completed, candidates: [general, strong]).option(.strongman)

        #expect(option.exercises.first?.candidateID == "strong",
                       "the alphabetical tie-break must not beat style membership")
        #expect(option.exercises.first?.isInStyle == true)
    }

    /// A style with nothing at all still produces a launchable general plan
    /// rather than an empty screen.
    @Test func aStyleWithAnEmptyPoolStillPlansFromTheFallback() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let general = styled("general", "Machine Press", ["chest"], types: [.strength])

        let option = generate(completed: completed, candidates: [general]).option(.strongman)

        #expect(option.isLaunchable)
        #expect(option.inStyleExerciseCount == 0)
        #expect(option.exercises.count == 1)
    }

    // MARK: - Cap, determinism, plans

    @Test func zeroHistoryCoversEveryTrackedGroupWithoutTrimmingPastTwentySets() {
        let candidates = MuscleGroup.allCases.enumerated().map {
            candidate("id-\($0.offset)", "Exercise \(String(format: "%02d", $0.offset))",
                      primary: [$0.element.rawValue])
        }
        let bundle = generate(completed: [:], candidates: candidates)

        for option in bundle.options where option.style != .personalized {
            #expect(!option.capTrimmingOccurred)
            #expect(option.plannedSetTotal == option.exercises.count * 3)
            let covered = Set(option.exercises.flatMap { $0.contributions.filter { $0.plannedSetContribution > 0 }.map(\.muscleID) })
            let covers = MuscleGroup.defaultTracked.allSatisfy { covered.contains($0.rawValue) }
            #expect(covers == option.unsupportedCoverage.isEmpty)
        }
        let fitness = bundle.option(.fitness)
        #expect(fitness.plannedSetTotal > 20)
        #expect(fitness.unsupportedCoverage.isEmpty)
        for group in MuscleGroup.defaultTracked {
            #expect(fitness.exercises.contains { $0.contributions.contains { $0.muscleID == group.rawValue } },
                          "\(group.rawValue) lost coverage")
        }
    }

    @Test func unsupportedGroupsAreListedWithReasonAndPlanIsKept() {
        let bundle = generate(completed: [:], candidates: [candidate("c", "Bench", primary: ["chest"])],
                              tracked: [.chest, .lats])
        let option = bundle.option(.fitness)

        #expect(option.isLaunchable)
        #expect(option.unsupportedCoverage.map(\.muscleID) == ["lats"])
        #expect(option.unsupportedCoverage.first?.reason == .noEligibleExercise)
        #expect(option.rationale?.whyWorkout.contains("Not covered: ") == true)
        #expect(option.rationale?.whyWorkout.contains("equipment, exclusions") == true)
    }

    @Test func setCountFollowsMostRecentExerciseElseThree() {
        let c = [candidate("c", "Bench", primary: ["chest"])]
        func plannedSets(_ sets: Int?) -> Int? {
            SuggestedWorkoutGenerator.generate(input: SuggestedWorkoutInput(
                completedSetsByMuscle: [:], candidates: c, trackedGroups: [.chest],
                preferredSetsPerExercise: 4, mostRecentExerciseWorkingSets: sets,
                trainingGoal: .hypertrophy)).option(.fitness).exercises.first?.plannedSets
        }
        #expect(plannedSets(nil) == 3)
        #expect(plannedSets(5) == 5)
        #expect(plannedSets(2) == 2)
    }

    @Test func firstPrescriptionIsFlatByGoalAndHistoryRestoresGoalRange() {
        let c = [candidate("c", "Bench", primary: ["chest"])]
        for (goal, reps) in [(TrainingGoal.strength, 3), (.hypertrophy, 8), (.endurance, 20)] {
            let option = generate(completed: [:], candidates: c, tracked: [.chest], goal: goal).option(.fitness)
            #expect(option.exercises.first?.repRange == reps...reps)
            #expect(option.plan.items.first?.reps == reps)
            #expect(option.exercises.first?.plannedSets == 3)
        }
        let withHistory = generate(completed: [:], candidates: c, tracked: [.chest],
                                   goal: .hypertrophy, historyWorkoutCount: 2).option(.fitness)
        #expect(withHistory.exercises.first?.repRange == TrainingGoal.hypertrophy.repRange)
    }

    @Test func resultsDoNotDependOnCandidateOrDictionaryInputOrder() {
        let pairs = MuscleGroup.allCases.enumerated().map { ($0.element.rawValue, Double($0.offset % 4)) }
        let candidates = [
            candidate("a", "Beta", primary: ["chest", "lats"]),
            candidate("b", "Alpha", primary: ["quadriceps"], secondary: ["glutes"]),
            candidate("c", "Gamma", mechanics: .isolation, primary: ["biceps"]),
        ]
        let forward = generate(completed: Dictionary(uniqueKeysWithValues: pairs),
                               candidates: candidates)
        let reverse = generate(completed: Dictionary(uniqueKeysWithValues: pairs.reversed()),
                               candidates: candidates.reversed())

        #expect(forward.options.map { $0.exercises.map(\.candidateID) } ==
                       reverse.options.map { $0.exercises.map(\.candidateID) })
        #expect(forward.options.map(\.remainingDeficits) ==
                       reverse.options.map(\.remainingDeficits))
    }

    @Test func everyStyleStartsFromTheOriginalCompletedSnapshot() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let chest = candidate("chest", "Chest", primary: ["chest"])

        let bundle = generate(completed: completed, candidates: [chest])

        for option in bundle.options where option.style != .personalized {
            #expect(option.initialDeficits["chest"] == 4)
            #expect(option.remainingDeficits["chest"] == 1)
            #expect(option.exercises.count == 1)
        }
    }

    @Test func engineContextGeneratesAllStylesWithEvaluationAndProvenance() throws {
        let candidates = TrainingEngineBridge.exerciseRecords.map { record in
            SuggestedExerciseCandidate(
                id: record.exerciseId,
                name: record.name,
                mechanics: Mechanics(rawValue: record.mechanic ?? "") ?? .compound,
                primaryMuscles: record.direct,
                secondaryMuscles: record.indirect,
                volumeEligible: record.volumeEligible,
                trainingTypes: ExerciseTrainingType.decode(
                    record.category == "powerlifting" ? ["strength", "powerlifting"]
                    : record.category == "olympic weightlifting" ? ["strength", "olympic_weightlifting"]
                    : record.category == "strongman" ? ["strength", "strongman"]
                    : ["strength"]),
                modalities: record.equipment?.lowercased() == "body only" ? [.bodyweight] : [],
                sportContexts: [.generalFitness])
        }
        let bundle = SuggestedWorkoutGenerator.generate(input: SuggestedWorkoutInput(
            completedSetsByMuscle: [:],
            candidates: candidates,
            historyWorkoutCount: 5,
            historyWorkingSetCount: 40,
            trackedGroups: [.chest, .lats],
            preferredSetsPerExercise: 4,
            trainingGoal: .hypertrophy,
            engineContext: SuggestedWorkoutEngineContext(
                schedule: .default,
                availableEquipment: Equipment.allCases,
                asOf: Date(timeIntervalSince1970: 1_750_000_000))))

        #expect(bundle.options.map(\.style) == SuggestedWorkoutStyle.allCases)
        for option in bundle.options where option.style != .personalized {
            #expect(option.isLaunchable)
            #expect(option.plannedSetTotal > 0)
            if option.style == .fitness {
                #expect(option.enginePlanID == "generated-plan")
                #expect(option.engineRevisionID == "r1")
                #expect(option.enginePlanJSON != nil)
            } else {
                #expect(option.enginePlanID == nil,
                             "non-Fitness style should use the fast facet-aware app solver")
            }
            #expect(option.initialDeficits["chest"] == 4)
            #expect(option.initialDeficits["lats"] == 4)
        }
        let bodyweight = bundle.option(.bodyweight)
        let bodyweightIDs = Set(TrainingEngineBridge.preferredExerciseIDs(for: .bodyweight))
        #expect(!bodyweight.exercises.isEmpty)
        let bodyweightNames = bodyweight.exercises.map(\.name).joined(separator: ", ")
        #expect(bodyweight.exercises.allSatisfy { bodyweightIDs.contains($0.candidateID) },
                      "Bodyweight chooser leaked a non-bodyweight movement: \(bodyweightNames)")
        #expect(!bodyweight.exercises.contains { $0.name.localizedCaseInsensitiveContains("clean and jerk") })
    }

    @Test func engineContextGeneratesLaunchableOptionsForDefaultTrackedGroups() {
        let bundle = SuggestedWorkoutGenerator.generate(input: SuggestedWorkoutInput(
            completedSetsByMuscle: [:],
            candidates: ExerciseLibrary.starter.map(SuggestedExerciseCandidate.init(template:)),
            trackedGroups: MuscleGroup.defaultTracked,
            preferredSetsPerExercise: CoachSchedulePreferences.default.desiredSetsPerExercise,
            trainingGoal: .hypertrophy,
            engineContext: SuggestedWorkoutEngineContext(
                schedule: .default,
                availableEquipment: Equipment.allCases,
                asOf: Date(timeIntervalSince1970: 1_750_000_000))))

        #expect(bundle.options.filter { $0.style != .personalized }.allSatisfy { $0.isLaunchable },
                      "default tracked groups produced empty options: \(bundle.options.map { ($0.style, $0.exercises.count) })")
    }

    @Test func engineContextWithCompletedHistoryStillGeneratesLaunchableOptions() throws {
        let asOf = Date(timeIntervalSince1970: 1_750_000_000)
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let session = try WorkoutRepository.createSession(
            title: "Prior workout", date: asOf.addingTimeInterval(-86_400), in: context)
        let record = try #require(
            TrainingEngineBridge.exerciseRecords.first { $0.volumeEligible && !$0.direct.isEmpty })
        let exercise = Exercise(
            name: record.name,
            category: .push,
            primaryMuscles: record.primaryMuscles,
            secondaryMuscles: record.secondaryMuscles,
            directMuscles: record.direct.compactMap(MuscleGroup.canonical),
            indirectMuscles: record.indirect.compactMap(MuscleGroup.canonical),
            stabilizerMuscles: record.stabilizers.compactMap(MuscleGroup.canonical),
            volumeEligible: record.volumeEligible,
            sourceExerciseID: record.exerciseId)
        context.insert(exercise)
        _ = try WorkoutRepository.addSet(
            to: session, exercise: exercise, weightKg: 50, reps: 8,
            completedAt: session.date, in: context)
        session.endedAt = session.date.addingTimeInterval(600)
        let historyData = try #require(
            TrainingEngineBridge.historyData(from: [session], subjectId: "suggestion-test"))

        let bundle = SuggestedWorkoutGenerator.generate(input: SuggestedWorkoutInput(
            completedSetsByMuscle: [:],
            candidates: ExerciseLibrary.starter.map(SuggestedExerciseCandidate.init(template:)),
            historyData: historyData,
            historyWorkoutCount: 1,
            historyWorkingSetCount: 1,
            trackedGroups: MuscleGroup.defaultTracked,
            preferredSetsPerExercise: CoachSchedulePreferences.default.desiredSetsPerExercise,
            trainingGoal: .hypertrophy,
            engineContext: SuggestedWorkoutEngineContext(
                schedule: .default,
                availableEquipment: Equipment.allCases,
                asOf: asOf)))

        #expect(bundle.options.filter { $0.style != .personalized }.allSatisfy { $0.isLaunchable },
                      "history produced empty options: \(bundle.options.map { ($0.style, $0.exercises.count) })")
    }

    @Test func alreadySatisfiedStylesStillOfferMaintenanceWorkouts() {
        let completed = satisfied(at: 4)
        let candidates = [candidate("chest", "Chest", primary: ["chest"])]

        for option in generate(completed: completed, candidates: candidates).options
            where option.style != .personalized {
            #expect(option.isLaunchable)
            #expect(option.exercises.count == 1)
            #expect(option.plan.items.count == 1)
            #expect(option.plannedSetTotal == 3)
            #expect(Array(option.remainingDeficits.values) ==
                           Array(repeating: 0.0, count: option.remainingDeficits.count))
            #expect(!option.capTrimmingOccurred)
        }
    }

    @Test func realCatalogStaysLaunchableWhenThisWeekHasNoRemainingGaps() {
        let completed = Dictionary(uniqueKeysWithValues: MuscleGroup.defaultTracked.map {
            ($0.rawValue, Double(suggestedWorkoutTargetSetsPerGroup))
        })
        let bundle = generate(completed: completed, candidates: starterCandidates())

        #expect(bundle.options.filter { $0.style != .personalized }.allSatisfy { $0.isLaunchable },
                      "covered weekly gaps must not disable the chooser")
    }

    @Test func plansAndCitationsAreExactAndResolvable() {
        let candidates = MuscleGroup.allCases.enumerated().map {
            candidate("id-\($0.offset)", "Exercise \($0.offset)", primary: [$0.element.rawValue])
        }
        let bundle = generate(completed: [:], candidates: candidates, sets: 4, goal: .endurance)

        #expect(bundle.options.map { $0.plan.name } ==
                       ["Lift", "Fitness Workout", "Bodyweight Workout", "Powerlifting Workout",
                        "Olympic Weightlifting Workout", "Strongman Workout"])
        for option in bundle.options where option.style != .personalized {
            #expect(option.plan.id == "coach-suggested-\(option.style.rawValue)")
            #expect(option.plan.source == .coachSuggested)
            #expect(option.plan.scheme == .strength)
            #expect(option.plan.items.map(\.targetSets) ==
                           Array(repeating: 4, count: option.plan.items.count))
            #expect(option.plan.items.map(\.reps) ==
                           Array(repeating: 20, count: option.plan.items.count))
            #expect(option.plan.items.allSatisfy { $0.loadLb == nil && $0.loadPercentage == nil })
            #expect(option.citationIDs == suggestedWorkoutCitationIDs)
            for citationID in option.citationIDs {
                #expect(CitationRegistry.citation(forId: citationID) != nil)
            }
        }
        #expect(suggestedWorkoutCitationIDs ==
                       ["acsmResistanceTraining2002", "acsmResistanceTraining2026",
                        "iversenTimeEfficient2021", "volumeDoseResponse", "pellandDoseResponse2026"])
        #expect(CitationRegistry.citation(forId: "volumeDoseResponse")?.url ==
                       "https://pubmed.ncbi.nlm.nih.gov/27433992/")
    }

    // MARK: - The real catalog

    /// The whole shipped catalog, mapped exactly as the app maps it. Every style
    /// has to produce a launchable plan from real data, not just from fixtures.
    @Test func everyStyleIsLaunchableFromTheRealCatalog() {
        let bundle = generate(completed: [:], candidates: starterCandidates())

        for option in bundle.options where option.style != .personalized {
            #expect(option.isLaunchable, "\(option.style) produced no plan")
            #expect(option.plannedSetTotal > 0)
            #expect(option.inStyleExerciseCount > 0,
                                 "\(option.style) borrowed its entire plan")
        }
        // Distinct styles must not collapse into the same plan — that was the
        // failure mode of the three tiers this replaced.
        let nonPersonalized = bundle.options.filter { $0.style != .personalized }
        let plans = Set(nonPersonalized.map { $0.exercises.map(\.candidateID) })
        #expect(plans.count == nonPersonalized.count)
    }

    /// The app can open the chooser before its asynchronous SwiftData seed has
    /// finished. The in-memory starter catalog is the fallback for that window,
    /// so it must produce the same launchable non-personalized style surface.
    @Test func canonicalStarterTemplatesProduceLaunchableOptions() {
        let candidates = ExerciseLibrary.starter.map(SuggestedExerciseCandidate.init(template:))
        let bundle = generate(completed: [:], candidates: candidates)

        #expect(bundle.options.count == SuggestedWorkoutStyle.allCases.count)
        #expect(bundle.options.filter { $0.style != .personalized }.allSatisfy { $0.isLaunchable })
    }

    @Test func representativeStarterSliceVectorizesFacetsDeterministically() throws {
        let templates = Array(ExerciseLibrary.starter.filter {
            !$0.primaryMuscles.isEmpty && !$0.secondaryMuscles.isEmpty
        }.prefix(60))
        #expect(!templates.isEmpty)
        let candidates = templates.enumerated().map { offset, template in
            SuggestedExerciseCandidate(
                id: "starter-\(offset)", name: template.name, mechanics: template.mechanics,
                primaryMuscles: template.directMuscles.map(\.rawValue),
                secondaryMuscles: template.indirectMuscles.map(\.rawValue),
                volumeEligible: template.volumeEligible,
                trainingTypes: template.trainingTypes,
                modalities: template.modalities,
                sportContexts: template.sportContexts
            )
        }

        let forward = generate(completed: [:], candidates: candidates)
        let reverse = generate(completed: [:], candidates: candidates.reversed())

        #expect(forward.options.map { $0.exercises.map(\.candidateID) } ==
                       reverse.options.map { $0.exercises.map(\.candidateID) })
        let emitted = try #require(forward.options.flatMap(\.exercises).first)
        #expect(emitted.contributions.contains { $0.weight == VolumeCredit.direct })
        #expect(forward.options.flatMap(\.exercises)
            .flatMap(\.contributions).contains { $0.weight == VolumeCredit.indirect })
    }

    @Test func fullStarterCatalogSharesOneIndexUsesInvertedListsAndStaysFast() {
        let candidates = starterCandidates()
        var indexMilliseconds: [Double] = []
        var generationMilliseconds: [Double] = []
        var last: SuggestedWorkoutBundle?
        for _ in 0..<7 {
            let bundle = generate(completed: [:], candidates: candidates)
            indexMilliseconds.append(milliseconds(bundle.diagnostics.vectorIndexBuildDuration))
            generationMilliseconds.append(milliseconds(bundle.diagnostics.allStylesGenerationDuration))
            last = bundle
        }
        let bundle = last!

        #expect(bundle.diagnostics.indexBuildCount == 1)
        #expect(bundle.diagnostics.rawCandidateCount == candidates.count)
        #expect(bundle.diagnostics.indexedCandidateCount > 0)
        #expect(bundle.diagnostics.indexedCandidateCount < candidates.count,
                          "volume-ineligible movements must be filtered out of the index")
        #expect(bundle.diagnostics.invertedListLookupCount > 0)
        #expect(bundle.diagnostics.invertedCandidateVisitCount > 0)
        #expect(bundle.diagnostics.fullCatalogScanCount == 0)
        #expect(
            bundle.diagnostics.invertedCandidateVisitCount <
            bundle.diagnostics.indexedCandidateCount * bundle.diagnostics.invertedListLookupCount
        )
        #expect(indexMilliseconds.max()! < 2_000)
        #expect(generationMilliseconds.max()! < 2_000)

        indexMilliseconds.sort()
        generationMilliseconds.sort()
        print("SuggestedWorkout median vector index: \(indexMilliseconds[3]) ms")
        print("SuggestedWorkout median six-style solve: \(generationMilliseconds[3]) ms")
    }

    // MARK: - Helpers

    private func starterCandidates() -> [SuggestedExerciseCandidate] {
        ExerciseLibrary.starter.enumerated().map { offset, template in
            SuggestedExerciseCandidate(
                id: "starter-\(offset)", name: template.name, mechanics: template.mechanics,
                primaryMuscles: template.directMuscles.map(\.rawValue),
                secondaryMuscles: template.indirectMuscles.map(\.rawValue),
                volumeEligible: template.volumeEligible,
                trainingTypes: template.trainingTypes,
                modalities: template.modalities,
                sportContexts: template.sportContexts
            )
        }
    }

    private func generate(completed: [String: Double],
                          candidates: some Sequence<SuggestedExerciseCandidate>,
                          tracked: Set<MuscleGroup> = MuscleGroup.defaultTracked,
                          sets: Int = 3,
                          goal: TrainingGoal = .hypertrophy,
                          historyWorkoutCount: Int = 0) -> SuggestedWorkoutBundle {
        SuggestedWorkoutGenerator.generate(input: SuggestedWorkoutInput(
            completedSetsByMuscle: completed,
            candidates: Array(candidates),
            historyWorkoutCount: historyWorkoutCount,
            trackedGroups: tracked,
            preferredSetsPerExercise: 4,
            mostRecentExerciseWorkingSets: sets,
            trainingGoal: goal
        ))
    }

    private func candidate(_ id: String, _ name: String,
                           mechanics: Mechanics = .compound,
                           primary: [String] = [], secondary: [String] = [])
        -> SuggestedExerciseCandidate {
        SuggestedExerciseCandidate(id: id, name: name, mechanics: mechanics,
                                   primaryMuscles: primary, secondaryMuscles: secondary)
    }

    private func styled(_ id: String, _ name: String, _ primary: [String],
                        types: [ExerciseTrainingType],
                        modalities: [ExerciseModality] = [],
                        mechanics: Mechanics = .compound) -> SuggestedExerciseCandidate {
        SuggestedExerciseCandidate(
            id: id, name: name, mechanics: mechanics,
            primaryMuscles: primary, secondaryMuscles: [],
            volumeEligible: true, trainingTypes: types, modalities: modalities,
            sportContexts: types == [.strength] ? [.generalFitness] : [])
    }

    private func satisfied(at sets: Double) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: MuscleGroup.allCases.map { ($0.rawValue, sets) })
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
#endif
