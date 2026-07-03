import XCTest
@testable import CadenceCore

/// Tests for the precomputed `ExerciseSearchIndex` that powers the exercise picker.
/// The picker was "extremely slow/jerky"; these lock in both correctness (parity
/// with the reference ranking) and speed (per-keystroke ranking over the full
/// ~1000-exercise catalog must be fast).
final class ExerciseSearchIndexTests: XCTestCase {

    private struct MockExercise: ExerciseSearchable, Equatable {
        let name: String
        let searchKeywords: [String]
        let isCustom: Bool
        init(_ name: String, keywords: [String] = [], custom: Bool = false) {
            self.name = name
            self.searchKeywords = keywords
            self.isCustom = custom
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

    func testEmptyQueryReturnsAllBuiltInsFirstAlphabetical() {
        let index = ExerciseSearchIndex(catalog)
        let results = index.rank("")
        XCTAssertEqual(results.count, catalog.count)
        // Custom exercises sort after built-ins.
        XCTAssertEqual(results.last?.name, "My Bench")
        // Built-ins are alphabetical.
        let builtIns = results.filter { !$0.isCustom }.map(\.name)
        XCTAssertEqual(builtIns, builtIns.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func testNamePrefixRanksFirst() {
        let index = ExerciseSearchIndex(catalog)
        let results = index.rank("bench")
        XCTAssertEqual(results.first?.name, "Bench Press", "name prefix should outrank keyword/other matches")
    }

    func testKeywordMatchSurfaces() {
        let index = ExerciseSearchIndex(catalog)
        let results = index.rank("pecs")
        XCTAssertTrue(results.contains { $0.name == "Bench Press" })
        XCTAssertTrue(results.contains { $0.name == "Cable Fly" })
        XCTAssertFalse(results.contains { $0.name == "Barbell Curl" })
    }

    func testMultiWordAndsTerms() {
        let index = ExerciseSearchIndex(catalog)
        let results = index.rank("cable chest")
        XCTAssertEqual(results.map(\.name), ["Cable Fly"], "both terms must match")
    }

    func testNoMatchReturnsEmpty() {
        let index = ExerciseSearchIndex(catalog)
        XCTAssertTrue(index.rank("zzzznotathing").isEmpty)
    }

    func testDiacriticInsensitive() {
        let index = ExerciseSearchIndex(catalog)
        XCTAssertTrue(index.rank("cafe").contains { $0.name == "Café Squat" })
        XCTAssertTrue(index.rank("café").contains { $0.name == "Café Squat" })
    }

    func testWhitespaceCollapsedAndTrimmed() {
        let index = ExerciseSearchIndex(catalog)
        XCTAssertEqual(index.rank("  bench   press  ").first?.name, "Bench Press")
    }

    func testBuiltInBeatsCustomOnEqualScore() {
        let index = ExerciseSearchIndex(catalog)
        let results = index.rank("bench")
        let benchNames = results.map(\.name)
        // "Bench Press" (name prefix, score 4) outranks "My Bench" (contains, score 3)
        XCTAssertLessThan(benchNames.firstIndex(of: "Bench Press")!,
                          benchNames.firstIndex(of: "My Bench")!)
    }

    // MARK: Parity with the reference one-shot API

    func testParityWithExerciseSearchRankOnRealCatalog() {
        let catalog = ExerciseLibrary.starter
        let index = ExerciseSearchIndex(catalog)
        for query in ["cable", "chest", "press", "cable chest", "lat", "curl", "squat", "over head", ""] {
            let viaIndex = index.rank(query).map(\.name)
            let viaRank = ExerciseSearch.rank(query, over: catalog).map(\.name)
            XCTAssertEqual(viaIndex, viaRank, "index and reference rank diverged for query: '\(query)'")
        }
    }

    // MARK: Performance (the core regression)

    /// The core regression guard, expressed relatively so it's independent of
    /// machine load: reusing a prebuilt index across keystrokes must be faster than
    /// rebuilding it every keystroke (which re-normalizes the whole catalog — the
    /// behavior that caused the jank). Also asserts a generous absolute ceiling to
    /// catch a catastrophic slowdown.
    func testReusingIndexBeatsRebuildingPerKeystroke() {
        let catalog = ExerciseLibrary.starter
        XCTAssertGreaterThan(catalog.count, 200, "expected a large catalog to stress search")
        let queries = ["b", "be", "ben", "benc", "bench", "c", "ca", "cab", "cable", "cable c"]
        let iterations = 10

        // The fix: build once, reuse across keystrokes.
        let index = ExerciseSearchIndex(catalog)
        let reuseStart = Date()
        for _ in 0..<iterations { for q in queries { _ = index.rank(q) } }
        let reuseElapsed = Date().timeIntervalSince(reuseStart)

        // The old behavior: rebuild the index (re-normalize the catalog) per query.
        let rebuildStart = Date()
        for _ in 0..<iterations { for q in queries { _ = ExerciseSearch.rank(q, over: catalog) } }
        let rebuildElapsed = Date().timeIntervalSince(rebuildStart)

        XCTAssertLessThan(reuseElapsed, rebuildElapsed,
                          "reusing the prebuilt index (\(reuseElapsed)s) must beat rebuilding per keystroke (\(rebuildElapsed)s)")
        // Generous absolute ceiling (100 reused ranks over the full catalog) so a
        // pathological regression still trips even on a heavily loaded CI box.
        XCTAssertLessThan(reuseElapsed, 10.0, "reused index ranking unexpectedly slow (\(reuseElapsed)s)")
    }

    func testNormalizeIsRegexFreeAndCorrect() {
        XCTAssertEqual(ExerciseSearch.normalize("  Incline\tBench   Press \n"), "incline bench press")
        XCTAssertEqual(ExerciseSearch.normalize("Café"), "cafe")
        XCTAssertEqual(ExerciseSearch.normalize(""), "")
    }
}
