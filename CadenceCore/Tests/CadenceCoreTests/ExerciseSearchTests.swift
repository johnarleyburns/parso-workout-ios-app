#if canImport(SwiftData)
import Testing
import SwiftData
@testable import CadenceCore

/// Field-testing §03 — faceted catalog + keyword-aware search.
struct ExerciseSearchTests {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    // MARK: Keyword search over the static catalog

    @Test func equipmentTermSurfacesAllCableMovements() {
        let results = ExerciseLibrary.search("cable", in: ExerciseLibrary.starter)
        #expect(results.count > 3, "‘cable’ should surface many cable movements")
        #expect(results.allSatisfy { $0.equipment == .cable },
                      "every ‘cable’ result should be a cable exercise")
        #expect(results.contains { $0.name == "Cable Fly" })
        #expect(results.contains { $0.name == "Triceps Pushdown" }, "pushdown is a cable move")
    }

    @Test func colloquialMuscleSynonymsResolve() {
        let lats = ExerciseLibrary.search("lats", in: ExerciseLibrary.starter)
        #expect(lats.contains { $0.name == "Lat Pulldown" })
        #expect(lats.contains { $0.name == "Pull-Up" })

        let pecs = ExerciseLibrary.search("pecs", in: ExerciseLibrary.starter)
        #expect(pecs.contains { $0.name == "Bench Press" }, "‘pecs’ should map to chest exercises")
    }

    @Test func forceTermSurfacesPushingMovements() {
        let push = ExerciseLibrary.search("push", in: ExerciseLibrary.starter)
        #expect(push.contains { $0.name == "Bench Press" })
        #expect(push.contains { $0.name == "Overhead Press" })
        #expect(!push.contains { $0.name == "Barbell Curl" }, "a curl is not a pushing movement")
    }

    @Test func namePrefixRanksAboveKeywordMatch() {
        let results = ExerciseLibrary.search("incline", in: ExerciseLibrary.starter)
        #expect(results.first?.name.localizedCaseInsensitiveContains("Incline") ?? false,
                      "a name match should rank first")
    }

    @Test func trainingDisciplineTermSurfacesOlympicLifts() {
        // "Snatch" carries no "olympic" substring in its name — only in its
        // `trainingTypes` facet (field-testing batch: universal search).
        let results = ExerciseLibrary.search("olympic", in: ExerciseLibrary.starter)
        #expect(results.contains { $0.name == "Snatch" },
                      "'olympic' should surface olympic-weightlifting movements by discipline, not just name")
        #expect(results.contains { $0.name == "Clean and Jerk" })
    }

    @Test func multiWordQueryAndsTerms() {
        let results = ExerciseLibrary.search("cable chest", in: ExerciseLibrary.starter)
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.equipment == .cable },
                      "both terms must match: cable + chest")
    }

    @Test func emptyQueryReturnsAllBuiltInsFirst() {
        let results = ExerciseLibrary.search("", in: ExerciseLibrary.starter)
        #expect(results.count == ExerciseLibrary.starter.count)
    }

    // MARK: Seeding & re-seed

    @Test func seedInsertsFacetedCatalog() throws {
        let ctx = try makeContext()
        #expect(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
        let bench = try WorkoutRepository.allExercises(ctx).first { $0.name == "Bench Press" }
        #expect(bench?.equipmentValue == .barbell)
        #expect(bench?.forceValue == .push)
        #expect(bench?.primaryMuscles.contains("chest") ?? false)
        #expect(!(bench?.searchKeywords.isEmpty ?? true))
    }

    @Test func reSeedIsIdempotentAndPreservesCustoms() throws {
        let ctx = try makeContext()
        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        _ = try WorkoutRepository.findOrCreateExercise(named: "My Custom Move", in: ctx)
        let countAfterCustom = try WorkoutRepository.allExercises(ctx).count

        #expect(!(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)), "nothing new to add")
        #expect(try WorkoutRepository.allExercises(ctx).count == countAfterCustom)
        #expect(try WorkoutRepository.allExercises(ctx).contains { $0.name == "My Custom Move" })
    }

    @Test func reSeedBackfillsLegacyBuiltIn() throws {
        let ctx = try makeContext()
        // Simulate a legacy built-in with no facets/keywords (pre-§03).
        ctx.insert(Exercise(name: "Bench Press", category: .push, isCustom: false))
        try ctx.save()
        #expect(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
        let bench = try WorkoutRepository.allExercises(ctx).filter { $0.name == "Bench Press" }
        #expect(bench.count == 1, "should backfill, not duplicate")
        #expect(bench.first?.equipmentValue == .barbell)
        #expect(!(bench.first?.searchKeywords.isEmpty ?? true))
    }

    @Test func reSeedRefreshesLegacyKeywordsAndMuscles() throws {
        let ctx = try makeContext()
        // This represents an installed row from the pre-faceted search index:
        // it has a name token, but no canonical muscle fields.
        ctx.insert(Exercise(name: "Bench Press", category: .push, isCustom: false,
                            searchKeywords: ["bench", "press"]))
        try ctx.save()

        #expect(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
        let bench = try #require(try WorkoutRepository.allExercises(ctx)
            .first { $0.name == "Bench Press" })
        #expect(bench.primaryMuscles.contains("chest"))
        #expect(bench.searchKeywords.contains("chest"))
        #expect(ExerciseSearchIndex([bench]).rank("chest").contains { $0.id == bench.id })
    }

    @Test func customExerciseGetsKeywords() throws {
        let ctx = try makeContext()
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: "Cable Hammer Curl", category: .pull, equipment: .cable,
            mechanics: .isolation, force: .pull, primaryMuscles: ["biceps"], in: ctx)
        #expect(ex.searchKeywords.contains("cable"))
        #expect(ex.searchKeywords.contains("biceps") || ex.searchKeywords.contains("bis"))
        let found = try WorkoutRepository.searchExercises("cable", in: ctx)
        #expect(found.contains { $0.id == ex.id })
    }
    @Test func catalogEnglishAliasFindsCanonicalExercise() {
        let results = ExerciseSearch.rank("Banded March", over: ExerciseLibrary.starter)
        #expect(results.contains { $0.sourceExerciseID == "Hip_Flexion_with_Band" })
    }

    @Test func releasedNamesSearchInGermanAndChineseWithoutChangingIdentity() {
        let german = ExerciseSearchIndex(ExerciseLibrary.starter, locale: Locale(identifier: "de"))
        #expect(german.rank("Zehenheben").contains { $0.sourceExerciseID == "Standing_Toe_Raise" })
        let chinese = ExerciseSearchIndex(ExerciseLibrary.starter, locale: Locale(identifier: "zh-Hans"))
        #expect(chinese.rank("胫骨").contains { $0.sourceExerciseID == "Single-Leg_Tib_Bar_Raise" })
    }

}
#endif
