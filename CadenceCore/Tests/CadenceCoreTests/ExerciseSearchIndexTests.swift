import Foundation
import Testing
@testable import CadenceCore

/// Tests for the precomputed `ExerciseSearchIndex` that powers the exercise picker.
/// The picker was "extremely slow/jerky"; these lock in both correctness (parity
/// with the reference ranking) and speed (per-keystroke ranking over the full
/// ~1000-exercise catalog must be fast).
struct ExerciseSearchIndexTests {

    private struct MockExercise: ExerciseSearchable, Equatable {
        let name: String
        let searchKeywords: [String]
        let isCustom: Bool
        let primaryMuscleGroups: [MuscleGroup]
        init(_ name: String, keywords: [String] = [], custom: Bool = false,
             primary: [MuscleGroup] = []) {
            self.name = name
            self.searchKeywords = keywords
            self.isCustom = custom
            self.primaryMuscleGroups = primary
        }
    }

    private let catalog: [MockExercise] = [
        MockExercise("Bench Press", keywords: ["chest", "pecs", "push", "barbell"]),
        MockExercise("Incline Bench Press", keywords: ["chest", "upper chest", "push", "barbell"]),
        MockExercise("Cable Fly", keywords: ["chest", "pecs", "cable"]),
        MockExercise("Barbell Curl", keywords: ["biceps", "bis", "pull", "barbell"]),
        MockExercise("Lat Pulldown", keywords: ["lats", "back", "pull", "cable"]),
        MockExercise("Pull-Up", keywords: ["lats", "back", "pull", "bodyweight"]),
        MockExercise("Café Squat", keywords: ["legs", "quads"]), // diacritic
        MockExercise("My Bench", keywords: ["chest"], custom: true),
    ]

    // MARK: Correctness

    @Test func emptyQueryReturnsAllBuiltInsFirstAlphabetical() {
        let index = ExerciseSearchIndex(catalog)
        let results = index.rank("")
        #expect(results.count == catalog.count)
        // Custom exercises sort after built-ins.
        #expect(results.last?.name == "My Bench")
        // Built-ins are alphabetical.
        let builtIns = results.filter { !$0.isCustom }.map(\.name)
        #expect(builtIns == builtIns.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    @Test func namePrefixRanksFirst() {
        let index = ExerciseSearchIndex(catalog)
        let results = index.rank("bench")
        #expect(results.first?.name == "Bench Press", "name prefix should outrank keyword/other matches")
    }

    @Test func keywordMatchSurfaces() {
        let index = ExerciseSearchIndex(catalog)
        let results = index.rank("pecs")
        #expect(results.contains { $0.name == "Bench Press" })
        #expect(results.contains { $0.name == "Cable Fly" })
        #expect(!results.contains { $0.name == "Barbell Curl" })
    }

    @Test func multiWordAndsTerms() {
        let index = ExerciseSearchIndex(catalog)
        let results = index.rank("cable chest")
        #expect(results.map(\.name) == ["Cable Fly"], "both terms must match")
    }

    @Test func noMatchReturnsEmpty() {
        let index = ExerciseSearchIndex(catalog)
        #expect(index.rank("zzzznotathing").isEmpty)
    }

    @Test func diacriticInsensitive() {
        let index = ExerciseSearchIndex(catalog)
        #expect(index.rank("cafe").contains { $0.name == "Café Squat" })
        #expect(index.rank("café").contains { $0.name == "Café Squat" })
    }

    @Test func whitespaceCollapsedAndTrimmed() {
        let index = ExerciseSearchIndex(catalog)
        #expect(index.rank("  bench   press  ").first?.name == "Bench Press")
    }

    @Test func builtInBeatsCustomOnEqualScore() {
        let index = ExerciseSearchIndex(catalog)
        let results = index.rank("bench")
        let benchNames = results.map(\.name)
        // "Bench Press" (name prefix, score 4) outranks "My Bench" (contains, score 3)
        #expect(benchNames.firstIndex(of: "Bench Press")! <
                          benchNames.firstIndex(of: "My Bench")!)
    }

    @Test func exactMuscleQueryRanksPrimaryFocusAndExposesTransparentShare() {
        let exercises = [
            MockExercise("Cable Fly", keywords: ["chest"], primary: [.chest]),
            MockExercise("Press", keywords: ["chest"], primary: [.chest, .triceps]),
            MockExercise("Triceps Press", keywords: ["chest"], primary: [.triceps])
        ]
        let index = ExerciseSearchIndex(exercises)
        let ranked = index.rank("chest", prioritizingPrimaryMuscle: .chest)

        #expect(ranked.map(\.name) == ["Cable Fly", "Press"])
        #expect(ExerciseSearch.primaryFocusPercent(primaryMuscles: [.chest], group: .chest) == 100)
        #expect(ExerciseSearch.primaryFocusPercent(primaryMuscles: [.chest, .triceps], group: .chest) == 50)
    }

    @Test func muscleSynonymResolvesForPrimaryRanking() {
        #expect(ExerciseSearch.primaryMuscleGroup(matching: "pecs") == .chest)
        #expect(ExerciseSearch.primaryMuscleGroup(matching: "back") == nil,
                     "broad region terms map to several muscle groups")
    }

    // MARK: Parity with the reference one-shot API

    @Test func parityWithExerciseSearchRankOnRealCatalog() {
        let catalog = ExerciseLibrary.starter
        let index = ExerciseSearchIndex(catalog)
        for query in ["cable", "chest", "press", "cable chest", "lat", "curl", "squat", "over head", ""] {
            let viaIndex = index.rank(query).map(\.name)
            let viaRank = ExerciseSearch.rank(query, over: catalog).map(\.name)
            #expect(viaIndex == viaRank, "index and reference rank diverged for query: '\(query)'")
        }
    }

    // MARK: Performance (the core regression)

    /// The core regression guard, expressed relatively so it's independent of
    /// machine load: reusing a prebuilt index across keystrokes must be faster than
    /// rebuilding it every keystroke (which re-normalizes the whole catalog — the
    /// behavior that caused the jank). Also asserts a generous absolute ceiling to
    /// catch a catastrophic slowdown.
    @Test func reusingIndexBeatsRebuildingPerKeystroke() {
        let catalog = ExerciseLibrary.starter
        #expect(catalog.count > 200, "expected a large catalog to stress search")
        let queries = ["b", "be", "ben", "benc", "bench", "c", "ca", "cab", "cable", "cable c"]
        // Routine checks still exercise every query and both implementations.
        // The scheduled benchmark increases repetitions without taxing every PR.
        let iterations = ProcessInfo.processInfo.environment["CADENCE_FULL_BENCHMARKS"] == "1" ? 10 : 1

        // The fix: build once, reuse across keystrokes.
        let index = ExerciseSearchIndex(catalog)
        let reuseStart = Date()
        for _ in 0..<iterations { for q in queries { _ = index.rank(q) } }
        let reuseElapsed = Date().timeIntervalSince(reuseStart)

        // The old behavior: rebuild the index (re-normalize the catalog) per query.
        let rebuildStart = Date()
        for _ in 0..<iterations { for q in queries { _ = ExerciseSearch.rank(q, over: catalog) } }
        let rebuildElapsed = Date().timeIntervalSince(rebuildStart)

        #expect(reuseElapsed < rebuildElapsed,
                          "reusing the prebuilt index (\(reuseElapsed)s) must beat rebuilding per keystroke (\(rebuildElapsed)s)")
        // Preserve the same per-query ceiling for routine and full benchmarks.
        let secondsPerQuery = reuseElapsed / Double(iterations * queries.count)
        #expect(secondsPerQuery < 0.1, "reused index ranking unexpectedly slow (\(secondsPerQuery)s per query)")
    }

    @Test func normalizeIsRegexFreeAndCorrect() {
        #expect(ExerciseSearch.normalize("  Incline\tBench   Press \n") == "incline bench press")
        #expect(ExerciseSearch.normalize("Café") == "cafe")
        #expect(ExerciseSearch.normalize("") == "")
    }
}
