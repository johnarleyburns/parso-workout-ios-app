import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

/// The value catalog behind the Watch Add Exercise screen and the iPhone
/// picker. It must answer the same questions the pickers used to answer from
/// `@Model` rows on the main actor.
final class ExerciseCatalogSnapshotTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    func testBuildCopiesEveryExerciseInNameOrder() throws {
        let snapshot = try ExerciseCatalogSnapshot.build(in: context)
        XCTAssertTrue(snapshot.isLoaded)
        XCTAssertEqual(snapshot.entries.count, try WorkoutRepository.allExercises(context).count)
        XCTAssertEqual(snapshot.entries.map(\.name), snapshot.entries.map(\.name).sorted())
    }

    func testEmptyPlaceholderIsNotLoaded() {
        XCTAssertFalse(ExerciseCatalogSnapshot.empty.isLoaded)
        XCTAssertTrue(ExerciseCatalogSnapshot.empty.entries.isEmpty)
    }

    func testEntryFacetsMatchTheModel() throws {
        let bench = try XCTUnwrap(try WorkoutRepository.allExercises(context).first { $0.name == "Bench Press" })
        let entry = ExerciseCatalogEntry(exercise: bench)
        XCTAssertEqual(entry.id, bench.id)
        XCTAssertEqual(entry.searchKeywords, bench.searchKeywords)
        XCTAssertEqual(entry.primaryMuscleGroups, bench.primaryMuscleGroups)
        XCTAssertEqual(entry.trainedMuscleGroups, bench.trainedMuscleGroups)
        XCTAssertEqual(entry.equipmentValue, bench.equipmentValue)
        XCTAssertEqual(entry.category, bench.categoryValue ?? .other)
        XCTAssertLessThanOrEqual(entry.summaryMuscleGroups.count, 3)
    }

    func testCategorySectionsCoverEveryEntryOnce() throws {
        let snapshot = try ExerciseCatalogSnapshot.build(in: context)
        let flattened = snapshot.categorySections.flatMap(\.entries)
        XCTAssertEqual(flattened.count, snapshot.entries.count)
        XCTAssertEqual(Set(flattened.map(\.id)), Set(snapshot.entries.map(\.id)))
        for section in snapshot.categorySections {
            XCTAssertTrue(section.entries.allSatisfy { $0.category == section.category })
            XCTAssertEqual(section.entries.map(\.name), section.entries.map(\.name).sorted())
        }
    }

    func testGroupListIsAlphabeticalAndOnlyThatGroup() throws {
        let snapshot = try ExerciseCatalogSnapshot.build(in: context)
        let chest = snapshot.entries(in: .chest)
        XCTAssertFalse(chest.isEmpty)
        XCTAssertTrue(chest.allSatisfy { $0.trainedMuscleGroups.contains(.chest) })
        let names = chest.map(\.name)
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        XCTAssertEqual(Set(names), Set(snapshot.facets.exercises(for: .chest).map(\.name)))
    }

    func testPopularResolvesAgainstTheStoredCatalog() throws {
        let snapshot = try ExerciseCatalogSnapshot.build(in: context)
        XCTAssertFalse(snapshot.popular.isEmpty)
        XCTAssertEqual(snapshot.popular.first?.name, "Bench Press")
    }

    func testSearchRanksAndCaps() throws {
        let snapshot = try ExerciseCatalogSnapshot.build(in: context)
        let results = snapshot.search("bench", limit: 8)
        XCTAssertFalse(results.isEmpty)
        XCTAssertLessThanOrEqual(results.count, 8)
        XCTAssertTrue(results[0].name.localizedCaseInsensitiveContains("bench"))
        XCTAssertTrue(snapshot.search("   ", limit: 8).isEmpty)
        XCTAssertTrue(snapshot.search("bench", limit: 0).isEmpty)
    }

    func testRecentIsNewestFirstAndLimited() throws {
        let all = try WorkoutRepository.allExercises(context)
        let pushdown = try XCTUnwrap(all.first { $0.name == "Triceps Pushdown" })
        let bench = try XCTUnwrap(all.first { $0.name == "Bench Press" })
        let session = try WorkoutRepository.createSession(in: context)
        let start = Date(timeIntervalSince1970: 1_000)
        try WorkoutRepository.addSet(to: session, exercise: pushdown, weightKg: 30, reps: 12,
                                     completedAt: start, in: context)
        try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5,
                                     completedAt: start.addingTimeInterval(60), in: context)
        try context.save()

        let snapshot = try ExerciseCatalogSnapshot.build(in: context, recentLimit: 12)
        XCTAssertEqual(snapshot.recent.map(\.name), ["Bench Press", "Triceps Pushdown"])
        XCTAssertEqual(try ExerciseCatalogSnapshot.build(in: context, recentLimit: 1).recent.map(\.name),
                       ["Bench Press"])
        XCTAssertTrue(try ExerciseCatalogSnapshot.build(in: context, recentLimit: 0).recent.isEmpty)
    }

    func testCustomExerciseEntry() throws {
        let custom = Exercise(name: "Cable Y Raise", isCustom: true, primaryMuscles: ["deltoids"])
        context.insert(custom)
        try context.save()
        let entry = try XCTUnwrap(try ExerciseCatalogSnapshot.build(in: context).entries.first { $0.name == "Cable Y Raise" })
        XCTAssertTrue(entry.isCustom)
        XCTAssertEqual(entry.category, .other)
        XCTAssertEqual(entry.summaryMuscleGroups, MuscleGroup.canonicalize(["deltoids"]))
    }

    func testExerciseByIDResolvesTheLiveModel() throws {
        let bench = try XCTUnwrap(try WorkoutRepository.allExercises(context).first { $0.name == "Bench Press" })
        XCTAssertEqual(ExerciseCatalogSnapshot.exercise(id: bench.id, in: context)?.name, "Bench Press")
        XCTAssertNil(ExerciseCatalogSnapshot.exercise(id: UUID(), in: context))
    }

    func testChangeSignalIsTheMostRecentlyEditedExercise() throws {
        let edited = try XCTUnwrap(try WorkoutRepository.allExercises(context).first)
        edited.updatedAt = Date().addingTimeInterval(3_600)
        try context.save()
        let newest = try context.fetch(ExerciseCatalogSnapshot.changeSignalDescriptor)
        XCTAssertEqual(newest.map(\.id), [edited.id])
    }

    func testLoadBuildsOnABackgroundContext() async throws {
        let container = try XCTUnwrap(self.container)
        let snapshot = await ExerciseCatalogSnapshot.load(from: container, recentLimit: 5)
        XCTAssertTrue(snapshot.isLoaded)
        XCTAssertEqual(snapshot.entries.count, ExerciseLibrary.starter.count)
    }

    func testSwapPresenterPreparesEveryOtherExercise() async throws {
        let bench = try XCTUnwrap(try WorkoutRepository.allExercises(context).first { $0.name == "Bench Press" })
        let source = ExerciseSwapCandidates.prepared(bench)
        XCTAssertEqual(source.id, bench.id.uuidString)
        XCTAssertFalse(source.direct.isEmpty)
        let container = try XCTUnwrap(self.container)
        let presenter = await ExerciseSwapCandidates.presenter(source: source, container: container)
        XCTAssertEqual(presenter.candidates.count, ExerciseLibrary.starter.count - 1)
        XCTAssertFalse(presenter.candidates.contains { $0.id == source.id })
        XCTAssertFalse(presenter.results(for: presenter.defaultType).isEmpty)
    }
}

/// The Watch resolves exercises by exact name with a one-row fetch instead of
/// loading the whole catalog on the first lookup of every workout.
final class WatchStrengthFlowExerciseLookupTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    func testExactNameUsesTheStoredExerciseWithoutCreatingOne() throws {
        let before = try WorkoutRepository.allExercises(context).count
        let model = WatchStrengthFlowModel(context: context)
        model.start()
        model.addExercise(named: "Bench Press")
        XCTAssertEqual(try WorkoutRepository.allExercises(context).count, before)
        XCTAssertEqual(model.exerciseList.map(\.exercise.name), ["Bench Press"])
    }

    func testDifferentCaseStillResolvesTheBuiltIn() throws {
        let before = try WorkoutRepository.allExercises(context).count
        let model = WatchStrengthFlowModel(context: context)
        model.start()
        model.addExercise(named: "bench press")
        XCTAssertEqual(try WorkoutRepository.allExercises(context).count, before)
        XCTAssertEqual(model.exerciseList.map(\.exercise.name), ["Bench Press"])
    }
}
