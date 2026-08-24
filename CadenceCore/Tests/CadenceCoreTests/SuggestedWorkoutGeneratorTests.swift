import XCTest
@testable import CadenceCore

/// The generator after the DB++ adoption (decision D6): one 4-set-per-group
/// target, five training styles, and a fallback pass that keeps a style from
/// silently abandoning a muscle it cannot reach.
final class SuggestedWorkoutGeneratorTests: XCTestCase {

    // MARK: - Target and style shape

    func testEveryStyleSolvesTheSameMinimumTarget() {
        let bundle = generate(completed: [:], candidates: [])

        XCTAssertEqual(bundle.options.map(\.style), SuggestedWorkoutStyle.allCases)
        XCTAssertEqual(bundle.options.count, 5)
        for option in bundle.options {
            XCTAssertEqual(option.initialDeficits.count, MuscleGroup.defaultTracked.count)
            XCTAssertTrue(option.initialDeficits.values.allSatisfy { $0 == 4 })
            XCTAssertEqual(option.remainingDeficits, option.initialDeficits)
            XCTAssertFalse(option.isLaunchable)
        }
    }

    /// Only tracked groups get a deficit — otherwise the solver spends slots on
    /// groups the catalog cannot train (decision D4, `tibialis` has no direct
    /// exercise anywhere in the database).
    func testUntrackedGroupsGetNoDeficit() {
        let bundle = generate(completed: [:], candidates: [], tracked: [.chest, .lats])

        XCTAssertEqual(bundle.option(.fitness).initialDeficits, ["chest": 4, "lats": 4])
        XCTAssertNil(bundle.option(.fitness).initialDeficits["tibialis"])
    }

    func testCompletedMusclesNormalizeMergeAndIgnoreUnknownValues() {
        let bundle = generate(
            completed: [" Lats ": 1.5, "lats": 2.0, "LATS\n": 0.5,
                        "unknown": 99, "  ": 99],
            candidates: []
        )

        XCTAssertEqual(bundle.option(.fitness).initialDeficits["lats"], 0)
        XCTAssertNil(bundle.option(.fitness).initialDeficits["unknown"])
    }

    // MARK: - Greedy selection

    func testLargestDeficitIsSelectedFirst() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 2
        let chest = candidate("chest", "Zulu Chest", primary: ["chest"])
        let lats = candidate("lats", "Alpha Lats", primary: ["lats"])

        let option = generate(completed: completed, candidates: [lats, chest]).option(.fitness)

        XCTAssertEqual(option.exercises.map(\.candidateID), ["chest", "lats"])
    }

    func testMultiDeficitExerciseWinsByExactCappedScore() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let single = candidate("single", "Single", primary: ["chest"])
        let combo = candidate("combo", "Combo", primary: ["chest", "lats"])

        let option = generate(completed: completed, candidates: [single, combo]).option(.fitness)

        XCTAssertEqual(option.exercises.first?.candidateID, "combo")
        XCTAssertEqual(option.exercises.first?.selectionScore ?? .nan, 6, accuracy: 1e-12)
    }

    func testDirectAndIndirectContributionsUpdateDeficitsAndPrimaryWins() throws {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let mixed = candidate(
            "mixed", "Mixed", primary: [" chest "],
            secondary: ["CHEST", " lats ", "unknown", "  "]
        )

        let option = generate(completed: completed, candidates: [mixed]).option(.fitness)
        let exercise = try XCTUnwrap(option.exercises.first)

        XCTAssertEqual(exercise.selectionScore, 4.5, accuracy: 1e-12)
        // Contributions are emitted in dimension order, which is
        // MuscleGroup.canonicalOrder — descending muscle mass — so lats precedes chest.
        XCTAssertEqual(exercise.contributions.map(\.muscleID), ["lats", "chest"])
        XCTAssertEqual(exercise.contributions.map(\.weight), [VolumeCredit.indirect, VolumeCredit.direct])
        XCTAssertEqual(option.remainingDeficits["chest"] ?? .nan, 1, accuracy: 1e-12)
        XCTAssertEqual(option.remainingDeficits["lats"] ?? .nan, 2.5, accuracy: 1e-12)
    }

    func testScoreCapsCreditAndIgnoresSatisfiedMuscles() {
        var completed = satisfied(at: 4)
        completed["chest"] = 3
        let exercise = candidate("combo", "Combo", primary: ["chest", "lats"])

        let option = generate(completed: completed, candidates: [exercise]).option(.fitness)

        XCTAssertEqual(option.exercises.first?.selectionScore ?? .nan, 1, accuracy: 1e-12)
        XCTAssertEqual(option.remainingDeficits["chest"] ?? .nan, 0, accuracy: 1e-12)
        XCTAssertEqual(option.remainingDeficits["lats"] ?? .nan, 0, accuracy: 1e-12)
    }

    func testPreferredSetValuesChangePlannedSetsScoresAndContributions() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let combo = candidate("combo", "Combo", primary: ["chest", "lats"])

        let three = generate(completed: completed, candidates: [combo], sets: 3).option(.fitness)
        let four = generate(completed: completed, candidates: [combo], sets: 4).option(.fitness)

        XCTAssertEqual(three.exercises.first?.plannedSets, 3)
        XCTAssertEqual(three.exercises.first?.selectionScore ?? .nan, 6, accuracy: 1e-12)
        XCTAssertEqual(four.exercises.first?.plannedSets, 4)
        XCTAssertEqual(four.exercises.first?.selectionScore ?? .nan, 8, accuracy: 1e-12)
        XCTAssertEqual(four.exercises.first?.contributions.map(\.plannedSetContribution), [4, 4])
    }

    func testSelectedExerciseNeverDuplicatesAndUnresolvedDeficitTerminates() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let chest = candidate("only", "Only Chest", primary: ["chest"])

        let option = generate(completed: completed, candidates: [chest]).option(.fitness)

        XCTAssertEqual(option.exercises.map(\.candidateID), ["only"])
        XCTAssertEqual(option.remainingDeficits["chest"] ?? .nan, 1, accuracy: 1e-12)
        XCTAssertEqual(option.remainingDeficits["lats"] ?? .nan, 4, accuracy: 1e-12)
        XCTAssertEqual(option.unresolvedDeficits["chest"], 1)
        XCTAssertEqual(option.unresolvedDeficits["lats"], 4)
    }

    func testEqualDeficitsPrioritizeLargerMusclesBeforeCatalogOrder() {
        var completed = satisfied(at: 4)
        completed["biceps"] = 0
        completed["quadriceps"] = 0
        let biceps = candidate("biceps", "Alpha Biceps", primary: ["biceps"])
        let quads = candidate("quads", "Zulu Quads", primary: ["quadriceps"])

        let option = generate(completed: completed, candidates: [biceps, quads]).option(.fitness)

        XCTAssertEqual(option.exercises.map(\.candidateID), ["quads", "biceps"])
        XCTAssertLessThan(MuscleGroup.massPriority(for: .quadriceps),
                          MuscleGroup.massPriority(for: .biceps))
    }

    func testSameMuscleEqualScorePrefersCompoundBeforeOtherTieBreaks() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let isolation = candidate("isolation", "Alpha", mechanics: .isolation, primary: ["chest"])
        let compound = candidate("compound", "Zulu", primary: ["chest"])

        let option = generate(completed: completed, candidates: [isolation, compound]).option(.fitness)

        XCTAssertEqual(option.exercises.first?.selectionScore, 3)
        XCTAssertEqual(option.exercises.first?.candidateID, "compound")
    }

    func testSameMuscleAndMechanicsPrefersBroaderMuscleInvolvementEvenWhenSatisfied() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let narrow = candidate("narrow", "Alpha", primary: ["chest"])
        let broad = candidate("broad", "Zulu", primary: ["chest"], secondary: ["biceps"])

        let option = generate(completed: completed, candidates: [narrow, broad]).option(.fitness)

        XCTAssertEqual(option.exercises.first?.selectionScore, 3)
        XCTAssertEqual(option.exercises.first?.candidateID, "broad")
    }

    func testTieBreakPrefersCompoundThenLocalizedName() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let isolation = candidate("isolation", "Alpha", mechanics: .isolation, primary: ["chest"])
        let compound = candidate("compound", "Zulu", primary: ["chest"])
        XCTAssertEqual(
            generate(completed: completed, candidates: [isolation, compound]).option(.fitness)
                .exercises.first?.candidateID,
            "compound"
        )

        let alpha = candidate("alpha", "Alpha", primary: ["chest"])
        let zulu = candidate("zulu", "Zulu", primary: ["chest"])
        XCTAssertEqual(
            generate(completed: completed, candidates: [zulu, alpha]).option(.fitness)
                .exercises.first?.candidateID,
            "alpha"
        )
    }

    func testCaseInsensitiveDuplicateNamesMergeWithStableIDTieBreak() throws {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let laterID = candidate("z-id", " Press ", primary: ["chest"])
        let earlierID = candidate("a-id", "press", secondary: ["lats"])

        let option = generate(completed: completed, candidates: [laterID, earlierID]).option(.fitness)
        let exercise = try XCTUnwrap(option.exercises.first)

        XCTAssertEqual(exercise.candidateID, "a-id")
        XCTAssertEqual(exercise.name, "press")
        XCTAssertEqual(exercise.contributions.map(\.muscleID), ["lats", "chest"])
        XCTAssertEqual(option.exercises.count, 1)
    }

    // MARK: - Volume eligibility

    /// Stretching, plyometrics and cardio can never be prescribed as strength
    /// work, whatever muscles they list (decision D3).
    func testVolumeIneligibleMovementsAreNeverSuggested() {
        var completed = satisfied(at: 4)
        completed["hamstrings"] = 0
        let stretch = SuggestedExerciseCandidate(
            id: "stretch", name: "Standing Hamstring Stretch", mechanics: .isolation,
            primaryMuscles: ["hamstrings"], secondaryMuscles: [],
            volumeEligible: false, trainingTypes: [.stretching])

        let bundle = generate(completed: completed, candidates: [stretch])

        for option in bundle.options {
            XCTAssertTrue(option.exercises.isEmpty, "\(option.style) suggested a stretch")
            XCTAssertEqual(option.remainingDeficits["hamstrings"], 4)
        }
    }

    // MARK: - Styles

    func testEachStylePrefersItsOwnMovementsForTheSameGap() {
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

        XCTAssertEqual(bundle.option(.olympic).exercises.first?.candidateID, "oly")
        XCTAssertEqual(bundle.option(.strongman).exercises.first?.candidateID, "strong")
        XCTAssertEqual(bundle.option(.powerlifting).exercises.first?.candidateID, "power")
        XCTAssertEqual(bundle.option(.bodyweight).exercises.first?.candidateID, "body")
        XCTAssertEqual(bundle.option(.fitness).exercises.first?.candidateID, "general")
        // A 4-set gap and 3 sets per exercise leaves a remainder, so each plan
        // takes a second movement too — but the style's own is always picked first.
        for option in bundle.options {
            XCTAssertEqual(option.exercises.first?.isInStyle, true, "\(option.style)")
        }
    }

    /// NFR-8: a style narrows the movements, it does not abandon a muscle. When
    /// the style pool cannot reach a gap, the second pass fills it from the whole
    /// catalog and the option reports how much it borrowed.
    func testStyleFallsBackToGeneralMovementsForGapsItCannotReach() throws {
        var completed = satisfied(at: 4)
        completed["quadriceps"] = 0
        completed["biceps"] = 0
        let oly = styled("oly", "Snatch", ["quadriceps"], types: [.strength, .olympicWeightlifting])
        let curl = styled("curl", "Cable Curl", ["biceps"], types: [.strength],
                          mechanics: .isolation)

        let option = generate(completed: completed, candidates: [oly, curl]).option(.olympic)

        XCTAssertEqual(option.exercises.map(\.candidateID), ["oly", "curl"])
        XCTAssertEqual(option.exercises.map(\.isInStyle), [true, false])
        XCTAssertEqual(option.inStyleExerciseCount, 1)
        XCTAssertEqual(option.remainingDeficits["biceps"] ?? .nan, 1, accuracy: 1e-12)
    }

    /// The fallback runs second, so the style's own movement wins a gap even when
    /// a general movement scores identically.
    func testInStyleMovementWinsAnExactTieAgainstTheFallback() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let general = styled("general", "Alpha Press", ["chest"], types: [.strength])
        let strong = styled("strong", "Zulu Log Press", ["chest"], types: [.strength, .strongman])

        let option = generate(completed: completed, candidates: [general, strong]).option(.strongman)

        XCTAssertEqual(option.exercises.first?.candidateID, "strong",
                       "the alphabetical tie-break must not beat style membership")
        XCTAssertEqual(option.exercises.first?.isInStyle, true)
    }

    /// A style with nothing at all still produces a launchable general plan
    /// rather than an empty screen.
    func testAStyleWithAnEmptyPoolStillPlansFromTheFallback() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let general = styled("general", "Machine Press", ["chest"], types: [.strength])

        let option = generate(completed: completed, candidates: [general]).option(.strongman)

        XCTAssertTrue(option.isLaunchable)
        XCTAssertEqual(option.inStyleExerciseCount, 0)
        XCTAssertEqual(option.exercises.count, 1)
    }

    // MARK: - Cap, determinism, plans

    func testCapTrimmingRemovesTailAndRecomputesRemainingDeficits() {
        let candidates = MuscleGroup.allCases.enumerated().map {
            candidate("id-\($0.offset)", "Exercise \(String(format: "%02d", $0.offset))",
                      primary: [$0.element.rawValue])
        }
        let bundle = generate(completed: [:], candidates: candidates)

        for option in bundle.options {
            XCTAssertLessThanOrEqual(option.plannedSetTotal, suggestedWorkoutPlannedSetCap)
            XCTAssertTrue(option.capTrimmingOccurred)
        }
        let fitness = bundle.option(.fitness)
        XCTAssertEqual(fitness.plannedSetTotal, 18)
        let expectedIDs = MuscleGroup.descendingMassOrder
            .filter { MuscleGroup.defaultTracked.contains($0) }
            .prefix(6)
            .compactMap { group in candidates.first { $0.primaryMuscles == [group.rawValue] }?.id }
        XCTAssertEqual(fitness.exercises.map(\.candidateID), expectedIDs)
        XCTAssertEqual(fitness.remainingDeficits["glutes"], 1)
    }

    func testResultsDoNotDependOnCandidateOrDictionaryInputOrder() {
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

        XCTAssertEqual(forward.options.map { $0.exercises.map(\.candidateID) },
                       reverse.options.map { $0.exercises.map(\.candidateID) })
        XCTAssertEqual(forward.options.map(\.remainingDeficits),
                       reverse.options.map(\.remainingDeficits))
    }

    func testEveryStyleStartsFromTheOriginalCompletedSnapshot() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let chest = candidate("chest", "Chest", primary: ["chest"])

        let bundle = generate(completed: completed, candidates: [chest])

        for option in bundle.options {
            XCTAssertEqual(option.initialDeficits["chest"], 4)
            XCTAssertEqual(option.remainingDeficits["chest"], 1)
            XCTAssertEqual(option.exercises.count, 1)
        }
    }

    func testAlreadySatisfiedStylesAreEmptyAndNonLaunchable() {
        let completed = satisfied(at: 4)
        let candidates = [candidate("chest", "Chest", primary: ["chest"])]

        for option in generate(completed: completed, candidates: candidates).options {
            XCTAssertTrue(option.exercises.isEmpty)
            XCTAssertTrue(option.plan.items.isEmpty)
            XCTAssertEqual(option.plannedSetTotal, 0)
            XCTAssertFalse(option.isLaunchable)
            XCTAssertFalse(option.capTrimmingOccurred)
        }
    }

    func testPlansAndCitationsAreExactAndResolvable() {
        let candidates = MuscleGroup.allCases.enumerated().map {
            candidate("id-\($0.offset)", "Exercise \($0.offset)", primary: [$0.element.rawValue])
        }
        let bundle = generate(completed: [:], candidates: candidates, sets: 4, goal: .endurance)

        XCTAssertEqual(bundle.options.map { $0.plan.name },
                       ["Fitness Plan", "Bodyweight Plan", "Powerlifting Plan",
                        "Olympic Weightlifting Plan", "Strongman Plan"])
        for option in bundle.options {
            XCTAssertEqual(option.plan.id, "coach-suggested-\(option.style.rawValue)")
            XCTAssertEqual(option.plan.source, .coachSuggested)
            XCTAssertEqual(option.plan.scheme, .strength)
            XCTAssertEqual(option.plan.items.map(\.targetSets),
                           Array(repeating: 4, count: option.plan.items.count))
            XCTAssertEqual(option.plan.items.map(\.reps),
                           Array(repeating: 15, count: option.plan.items.count))
            XCTAssertTrue(option.plan.items.allSatisfy { $0.loadLb == nil && $0.loadPercentage == nil })
            XCTAssertEqual(option.citationIDs, suggestedWorkoutCitationIDs)
            for citationID in option.citationIDs {
                XCTAssertNotNil(CitationRegistry.citation(forId: citationID))
            }
        }
        XCTAssertEqual(suggestedWorkoutCitationIDs,
                       ["iversenTimeEfficient2021", "pellandFractionalSets2024",
                        "pellandDoseResponse2026"])
    }

    // MARK: - The real catalog

    /// The whole shipped catalog, mapped exactly as the app maps it. Every style
    /// has to produce a launchable plan from real data, not just from fixtures.
    func testEveryStyleIsLaunchableFromTheRealCatalog() {
        let bundle = generate(completed: [:], candidates: starterCandidates())

        for option in bundle.options {
            XCTAssertTrue(option.isLaunchable, "\(option.style) produced no plan")
            XCTAssertLessThanOrEqual(option.plannedSetTotal, suggestedWorkoutPlannedSetCap)
            XCTAssertGreaterThan(option.inStyleExerciseCount, 0,
                                 "\(option.style) borrowed its entire plan")
        }
        // Distinct styles must not collapse into the same plan — that was the
        // failure mode of the three tiers this replaced.
        let plans = Set(bundle.options.map { $0.exercises.map(\.candidateID) })
        XCTAssertEqual(plans.count, bundle.options.count)
    }

    func testRepresentativeStarterSliceVectorizesFacetsDeterministically() throws {
        let templates = Array(ExerciseLibrary.starter.filter {
            !$0.primaryMuscles.isEmpty && !$0.secondaryMuscles.isEmpty
        }.prefix(60))
        XCTAssertFalse(templates.isEmpty)
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

        XCTAssertEqual(forward.options.map { $0.exercises.map(\.candidateID) },
                       reverse.options.map { $0.exercises.map(\.candidateID) })
        let emitted = try XCTUnwrap(forward.options.flatMap(\.exercises).first)
        XCTAssertTrue(emitted.contributions.contains { $0.weight == VolumeCredit.direct })
        XCTAssertTrue(forward.options.flatMap(\.exercises)
            .flatMap(\.contributions).contains { $0.weight == VolumeCredit.indirect })
    }

    func testFullStarterCatalogSharesOneIndexUsesInvertedListsAndStaysFast() {
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

        XCTAssertEqual(bundle.diagnostics.indexBuildCount, 1)
        XCTAssertEqual(bundle.diagnostics.rawCandidateCount, candidates.count)
        XCTAssertGreaterThan(bundle.diagnostics.indexedCandidateCount, 0)
        XCTAssertLessThan(bundle.diagnostics.indexedCandidateCount, candidates.count,
                          "volume-ineligible movements must be filtered out of the index")
        XCTAssertGreaterThan(bundle.diagnostics.invertedListLookupCount, 0)
        XCTAssertGreaterThan(bundle.diagnostics.invertedCandidateVisitCount, 0)
        XCTAssertEqual(bundle.diagnostics.fullCatalogScanCount, 0)
        XCTAssertLessThan(
            bundle.diagnostics.invertedCandidateVisitCount,
            bundle.diagnostics.indexedCandidateCount * bundle.diagnostics.invertedListLookupCount
        )
        XCTAssertLessThan(indexMilliseconds.max()!, 2_000)
        XCTAssertLessThan(generationMilliseconds.max()!, 2_000)

        indexMilliseconds.sort()
        generationMilliseconds.sort()
        print("SuggestedWorkout median vector index: \(indexMilliseconds[3]) ms")
        print("SuggestedWorkout median five-style solve: \(generationMilliseconds[3]) ms")
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
                          goal: TrainingGoal = .hypertrophy) -> SuggestedWorkoutBundle {
        SuggestedWorkoutGenerator.generate(input: SuggestedWorkoutInput(
            completedSetsByMuscle: completed,
            candidates: Array(candidates),
            trackedGroups: tracked,
            preferredSetsPerExercise: sets,
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
