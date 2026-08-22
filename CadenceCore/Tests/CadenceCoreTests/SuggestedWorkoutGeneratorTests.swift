import XCTest
@testable import CadenceCore

final class SuggestedWorkoutGeneratorTests: XCTestCase {
    func testEmptyCompletedListCreatesThreeOrderedTierDeficits() {
        let bundle = generate(completed: [:], candidates: [])

        XCTAssertEqual(bundle.options.map(\.tier), [.minimum, .medium, .maximal])
        XCTAssertEqual(bundle.options.count, 3)
        for (option, target) in zip(bundle.options, [4.0, 8.0, 12.0]) {
            XCTAssertEqual(option.initialDeficits.count, MuscleCatalog.all.count)
            XCTAssertTrue(option.initialDeficits.values.allSatisfy { $0 == target })
            XCTAssertEqual(option.remainingDeficits, option.initialDeficits)
            XCTAssertFalse(option.isLaunchable)
        }
    }

    func testCompletedMusclesNormalizeMergeAndIgnoreUnknownValues() {
        let bundle = generate(
            completed: [" Lats ": 1.5, "lats": 2.0, "LATS\n": 0.5,
                        "unknown": 99, "  ": 99],
            candidates: []
        )

        XCTAssertEqual(bundle.minimum.initialDeficits["lats"], 0)
        XCTAssertEqual(bundle.medium.initialDeficits["lats"], 4)
        XCTAssertEqual(bundle.maximal.initialDeficits["lats"], 8)
        XCTAssertNil(bundle.minimum.initialDeficits["unknown"])
    }

    func testLargestDeficitIsSelectedFirst() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 2
        let chest = candidate("chest", "Zulu Chest", primary: ["chest"])
        let lats = candidate("lats", "Alpha Lats", primary: ["lats"])

        let option = generate(completed: completed, candidates: [lats, chest]).minimum

        XCTAssertEqual(option.exercises.map(\.candidateID), ["chest", "lats"])
    }

    func testMultiDeficitExerciseWinsByExactCappedScore() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let single = candidate("single", "Single", primary: ["chest"])
        let combo = candidate("combo", "Combo", primary: ["chest", "lats"])

        let option = generate(completed: completed, candidates: [single, combo]).minimum

        XCTAssertEqual(option.exercises.first?.candidateID, "combo")
        XCTAssertEqual(option.exercises.first?.selectionScore ?? .nan, 6, accuracy: 1e-12)
    }

    func testDirectAndIndirectContributionsUpdateDeficitsAndPrimaryWins() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let mixed = candidate(
            "mixed", "Mixed", primary: [" chest "],
            secondary: ["CHEST", " lats ", "unknown", "  "]
        )

        let option = generate(completed: completed, candidates: [mixed]).minimum
        let exercise = try! XCTUnwrap(option.exercises.first)

        XCTAssertEqual(exercise.selectionScore, 4.5, accuracy: 1e-12)
        XCTAssertEqual(exercise.contributions.map(\.muscleID), ["chest", "lats"])
        XCTAssertEqual(exercise.contributions.map(\.weight), [1.0, 0.5])
        XCTAssertEqual(option.remainingDeficits["chest"] ?? .nan, 1, accuracy: 1e-12)
        XCTAssertEqual(option.remainingDeficits["lats"] ?? .nan, 2.5, accuracy: 1e-12)
    }

    func testScoreCapsCreditAndIgnoresSatisfiedMuscles() {
        var completed = satisfied(at: 4)
        completed["chest"] = 3
        let exercise = candidate("combo", "Combo", primary: ["chest", "lats"])

        let option = generate(completed: completed, candidates: [exercise]).minimum

        XCTAssertEqual(option.exercises.first?.selectionScore ?? .nan, 1, accuracy: 1e-12)
        XCTAssertEqual(option.remainingDeficits["chest"] ?? .nan, 0, accuracy: 1e-12)
        XCTAssertEqual(option.remainingDeficits["lats"] ?? .nan, 0, accuracy: 1e-12)
    }

    func testPreferredSetValuesChangePlannedSetsScoresAndContributions() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let combo = candidate("combo", "Combo", primary: ["chest", "lats"])

        let three = generate(completed: completed, candidates: [combo], sets: 3).minimum
        let four = generate(completed: completed, candidates: [combo], sets: 4).minimum

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

        let option = generate(completed: completed, candidates: [chest]).minimum

        XCTAssertEqual(option.exercises.map(\.candidateID), ["only"])
        XCTAssertEqual(option.remainingDeficits["chest"] ?? .nan, 1, accuracy: 1e-12)
        XCTAssertEqual(option.remainingDeficits["lats"] ?? .nan, 4, accuracy: 1e-12)
        XCTAssertEqual(option.unresolvedDeficits["chest"], 1)
        XCTAssertEqual(option.unresolvedDeficits["lats"], 4)
    }

    func testTieBreakPrefersLeadingDeficitCreditBeforeCoverage() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let leading = candidate("leading", "Zulu", primary: ["chest"])
        let spread = candidate("spread", "Alpha", secondary: ["chest", "lats"])

        let option = generate(completed: completed, candidates: [spread, leading]).minimum

        XCTAssertEqual(option.exercises.first?.selectionScore, 3)
        XCTAssertEqual(option.exercises.first?.candidateID, "leading")
    }

    func testTieBreakPrefersMoreDeficientMusclesCovered() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 3
        completed["upper-chest"] = 3.5
        completed["rear-delts"] = 3.5
        let fewer = candidate("fewer", "Alpha", primary: ["chest", "lats"])
        let more = candidate("more", "Zulu", primary: ["chest"],
                             secondary: ["upper-chest", "rear-delts"])

        let option = generate(completed: completed, candidates: [fewer, more]).minimum

        XCTAssertEqual(option.exercises.first?.selectionScore, 4)
        XCTAssertEqual(option.exercises.first?.candidateID, "more")
    }

    func testTieBreakPrefersCompoundThenLocalizedName() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        let isolation = candidate("isolation", "Alpha", mechanics: .isolation,
                                  primary: ["chest"])
        let compound = candidate("compound", "Zulu", primary: ["chest"])
        XCTAssertEqual(
            generate(completed: completed, candidates: [isolation, compound]).minimum
                .exercises.first?.candidateID,
            "compound"
        )

        let alpha = candidate("alpha", "Alpha", primary: ["chest"])
        let zulu = candidate("zulu", "Zulu", primary: ["chest"])
        XCTAssertEqual(
            generate(completed: completed, candidates: [zulu, alpha]).minimum
                .exercises.first?.candidateID,
            "alpha"
        )
    }

    func testCaseInsensitiveDuplicateNamesMergeWithStableIDTieBreak() {
        var completed = satisfied(at: 4)
        completed["chest"] = 0
        completed["lats"] = 0
        let laterID = candidate("z-id", " Press ", primary: ["chest"])
        let earlierID = candidate("a-id", "press", secondary: ["lats"])

        let option = generate(completed: completed, candidates: [laterID, earlierID]).minimum
        let exercise = try! XCTUnwrap(option.exercises.first)

        XCTAssertEqual(exercise.candidateID, "a-id")
        XCTAssertEqual(exercise.name, "press")
        XCTAssertEqual(exercise.contributions.map(\.muscleID), ["chest", "lats"])
        XCTAssertEqual(option.exercises.count, 1)
    }

    func testResultsDoNotDependOnCandidateOrDictionaryInputOrder() {
        let pairs = MuscleCatalog.all.enumerated().map { ($0.element.id, Double($0.offset % 4)) }
        let candidates = [
            candidate("a", "Beta", primary: ["chest", "lats"]),
            candidate("b", "Alpha", primary: ["quads"], secondary: ["glutes"]),
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

    func testEveryTierStartsFromOriginalCompletedSnapshot() {
        var completed = satisfied(at: 12)
        completed["chest"] = 0
        let chest = candidate("chest", "Chest", primary: ["chest"])

        let bundle = generate(completed: completed, candidates: [chest])

        XCTAssertEqual(bundle.minimum.initialDeficits["chest"], 4)
        XCTAssertEqual(bundle.medium.initialDeficits["chest"], 8)
        XCTAssertEqual(bundle.maximal.initialDeficits["chest"], 12)
        XCTAssertEqual(bundle.options.map { $0.remainingDeficits["chest"]! }, [1, 5, 9])
        XCTAssertEqual(bundle.options.map { $0.exercises.count }, [1, 1, 1])
    }

    func testCapTrimmingRemovesTailAndRecomputesRemainingDeficits() {
        let candidates = MuscleCatalog.all.enumerated().map {
            candidate("id-\($0.offset)", "Exercise \(String(format: "%02d", $0.offset))",
                      primary: [$0.element.id])
        }
        let bundle = generate(completed: [:], candidates: candidates)

        XCTAssertEqual(bundle.options.map(\.plannedSetTotal), [18, 30, 39])
        XCTAssertEqual(bundle.options.map(\.capTrimmingOccurred), [true, true, true])
        XCTAssertTrue(zip(bundle.options, [20, 30, 40]).allSatisfy { $0.plannedSetTotal <= $1 })
        XCTAssertEqual(bundle.minimum.exercises.map(\.candidateID),
                       Array(candidates.prefix(6)).map(\.id))
        XCTAssertEqual(bundle.minimum.remainingDeficits[MuscleCatalog.all[0].id], 1)
        XCTAssertEqual(bundle.minimum.remainingDeficits[MuscleCatalog.all[5].id], 1)
        XCTAssertEqual(bundle.minimum.remainingDeficits[MuscleCatalog.all[6].id], 4)
    }

    func testAlreadySatisfiedTiersAreEmptyAndNonLaunchable() {
        let completed = satisfied(at: 12)
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
        let candidates = MuscleCatalog.all.enumerated().map {
            candidate("id-\($0.offset)", "Exercise \($0.offset)", primary: [$0.element.id])
        }
        let bundle = generate(completed: [:], candidates: candidates,
                              sets: 4, goal: .endurance)

        XCTAssertEqual(bundle.options.map { $0.plan.name },
                       ["Minimum Plan", "Medium Plan", "Maximal Plan"])
        for option in bundle.options {
            XCTAssertEqual(option.plan.id, "coach-suggested-\(option.tier.rawValue)")
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
                       ["iversenTimeEfficient2021", "pellandFractionalSets2024"])
    }

    func testRepresentativeStarterSliceVectorizesFacetsDeterministically() throws {
        let templates = Array(ExerciseLibrary.starter.filter {
            !$0.primaryMuscles.isEmpty && !$0.secondaryMuscles.isEmpty
        }.prefix(60))
        XCTAssertFalse(templates.isEmpty)
        let candidates = templates.enumerated().map { offset, template in
            SuggestedExerciseCandidate(
                id: "starter-\(offset)", name: template.name, mechanics: template.mechanics,
                primaryMuscles: template.primaryMuscles,
                secondaryMuscles: template.secondaryMuscles
            )
        }

        let forward = generate(completed: [:], candidates: candidates)
        let reverse = generate(completed: [:], candidates: candidates.reversed())

        XCTAssertEqual(forward.options.map { $0.exercises.map(\.candidateID) },
                       reverse.options.map { $0.exercises.map(\.candidateID) })
        let emitted = try XCTUnwrap(forward.options.flatMap(\.exercises).first)
        XCTAssertTrue(emitted.contributions.contains { $0.weight == 1.0 })
        XCTAssertTrue(forward.options.flatMap(\.exercises)
            .flatMap(\.contributions).contains { $0.weight == 0.5 })
    }

    func testFullStarterCatalogSharesOneIndexUsesInvertedListsAndStaysFast() {
        let candidates = ExerciseLibrary.starter.enumerated().map { offset, template in
            SuggestedExerciseCandidate(
                id: "starter-\(offset)", name: template.name, mechanics: template.mechanics,
                primaryMuscles: template.primaryMuscles,
                secondaryMuscles: template.secondaryMuscles
            )
        }
        var indexMilliseconds: [Double] = []
        var generationMilliseconds: [Double] = []
        var last: SuggestedWorkoutBundle?
        for _ in 0..<7 {
            let bundle = generate(completed: [:], candidates: candidates)
            indexMilliseconds.append(milliseconds(bundle.diagnostics.vectorIndexBuildDuration))
            generationMilliseconds.append(milliseconds(bundle.diagnostics.threeTierGenerationDuration))
            last = bundle
        }
        let bundle = last!

        XCTAssertEqual(bundle.diagnostics.indexBuildCount, 1)
        XCTAssertEqual(bundle.diagnostics.rawCandidateCount, candidates.count)
        XCTAssertGreaterThan(bundle.diagnostics.indexedCandidateCount, 0)
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
        print("SuggestedWorkout median three-tier solve: \(generationMilliseconds[3]) ms")
    }

    private func generate(completed: [String: Double],
                          candidates: some Sequence<SuggestedExerciseCandidate>,
                          sets: Int = 3,
                          goal: TrainingGoal = .hypertrophy) -> SuggestedWorkoutBundle {
        SuggestedWorkoutGenerator.generate(input: SuggestedWorkoutInput(
            completedSetsByMuscle: completed,
            candidates: Array(candidates),
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

    private func satisfied(at sets: Double) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: MuscleCatalog.all.map { ($0.id, sets) })
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
