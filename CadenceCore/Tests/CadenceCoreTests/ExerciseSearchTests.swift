import XCTest
import SwiftData
@testable import CadenceCore

/// Field-testing §03 — faceted catalog + keyword-aware search.
final class ExerciseSearchTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    // MARK: Keyword search over the static catalog

    func testEquipmentTermSurfacesAllCableMovements() {
        let results = ExerciseLibrary.search("cable", in: ExerciseLibrary.starter)
        XCTAssertGreaterThan(results.count, 3, "‘cable’ should surface many cable movements")
        XCTAssertTrue(results.allSatisfy { $0.equipment == .cable },
                      "every ‘cable’ result should be a cable exercise")
        XCTAssertTrue(results.contains { $0.name == "Cable Fly" })
        XCTAssertTrue(results.contains { $0.name == "Triceps Pushdown" }, "pushdown is a cable move")
    }

    func testColloquialMuscleSynonymsResolve() {
        let lats = ExerciseLibrary.search("lats", in: ExerciseLibrary.starter)
        XCTAssertTrue(lats.contains { $0.name == "Lat Pulldown" })
        XCTAssertTrue(lats.contains { $0.name == "Pull-Up" })

        let pecs = ExerciseLibrary.search("pecs", in: ExerciseLibrary.starter)
        XCTAssertTrue(pecs.contains { $0.name == "Bench Press" }, "‘pecs’ should map to chest exercises")
    }

    func testForceTermSurfacesPushingMovements() {
        let push = ExerciseLibrary.search("push", in: ExerciseLibrary.starter)
        XCTAssertTrue(push.contains { $0.name == "Bench Press" })
        XCTAssertTrue(push.contains { $0.name == "Overhead Press" })
        XCTAssertFalse(push.contains { $0.name == "Barbell Curl" }, "a curl is not a pushing movement")
    }

    func testNamePrefixRanksAboveKeywordMatch() {
        let results = ExerciseLibrary.search("incline", in: ExerciseLibrary.starter)
        XCTAssertTrue(results.first?.name.localizedCaseInsensitiveContains("Incline") ?? false,
                      "a name match should rank first")
    }

    func testMultiWordQueryAndsTerms() {
        let results = ExerciseLibrary.search("cable chest", in: ExerciseLibrary.starter)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.equipment == .cable },
                      "both terms must match: cable + chest")
    }

    func testEmptyQueryReturnsAllBuiltInsFirst() {
        let results = ExerciseLibrary.search("", in: ExerciseLibrary.starter)
        XCTAssertEqual(results.count, ExerciseLibrary.starter.count)
    }

    // MARK: Seeding & re-seed

    func testSeedInsertsFacetedCatalog() throws {
        let ctx = try makeContext()
        XCTAssertTrue(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
        let bench = try WorkoutRepository.allExercises(ctx).first { $0.name == "Bench Press" }
        XCTAssertEqual(bench?.equipmentValue, .barbell)
        XCTAssertEqual(bench?.forceValue, .push)
        XCTAssertTrue(bench?.primaryMuscles.contains("chest") ?? false)
        XCTAssertFalse(bench?.searchKeywords.isEmpty ?? true)
    }

    func testReSeedIsIdempotentAndPreservesCustoms() throws {
        let ctx = try makeContext()
        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        _ = try WorkoutRepository.findOrCreateExercise(named: "My Custom Move", in: ctx)
        let countAfterCustom = try WorkoutRepository.allExercises(ctx).count

        XCTAssertFalse(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx), "nothing new to add")
        XCTAssertEqual(try WorkoutRepository.allExercises(ctx).count, countAfterCustom)
        XCTAssertTrue(try WorkoutRepository.allExercises(ctx).contains { $0.name == "My Custom Move" })
    }

    func testReSeedBackfillsLegacyBuiltIn() throws {
        let ctx = try makeContext()
        // Simulate a legacy built-in with no facets/keywords (pre-§03).
        ctx.insert(Exercise(name: "Bench Press", category: .push, isCustom: false))
        try ctx.save()
        XCTAssertTrue(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
        let bench = try WorkoutRepository.allExercises(ctx).filter { $0.name == "Bench Press" }
        XCTAssertEqual(bench.count, 1, "should backfill, not duplicate")
        XCTAssertEqual(bench.first?.equipmentValue, .barbell)
        XCTAssertFalse(bench.first?.searchKeywords.isEmpty ?? true)
    }

    func testReSeedRefreshesLegacyKeywordsAndMuscles() throws {
        let ctx = try makeContext()
        // This represents an installed row from the pre-faceted search index:
        // it has a name token, but no canonical muscle fields.
        ctx.insert(Exercise(name: "Bench Press", category: .push, isCustom: false,
                            searchKeywords: ["bench", "press"]))
        try ctx.save()

        XCTAssertTrue(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
        let bench = try XCTUnwrap(try WorkoutRepository.allExercises(ctx)
            .first { $0.name == "Bench Press" })
        XCTAssertTrue(bench.primaryMuscles.contains("chest"))
        XCTAssertTrue(bench.searchKeywords.contains("chest"))
        XCTAssertTrue(ExerciseSearchIndex([bench]).rank("chest").contains { $0.id == bench.id })
    }

    func testCustomExerciseGetsKeywords() throws {
        let ctx = try makeContext()
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: "Cable Hammer Curl", category: .pull, equipment: .cable,
            mechanics: .isolation, force: .pull, primaryMuscles: ["biceps"], in: ctx)
        XCTAssertTrue(ex.searchKeywords.contains("cable"))
        XCTAssertTrue(ex.searchKeywords.contains("biceps") || ex.searchKeywords.contains("bis"))
        let found = try WorkoutRepository.searchExercises("cable", in: ctx)
        XCTAssertTrue(found.contains { $0.id == ex.id })
    }
}
