#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// The value catalog behind the Watch Add Exercise screen and the iPhone
/// picker. It must answer the same questions the pickers used to answer from
/// `@Model` rows on the main actor.
final class ExerciseCatalogSnapshotTests {
    private var container: ModelContainer!
    private var context: ModelContext!

    init() throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    deinit {
        context = nil
        container = nil
    }

    @Test func buildCopiesEveryExerciseInNameOrder() throws {
        let snapshot = try ExerciseCatalogSnapshot.build(in: context)
        #expect(snapshot.isLoaded)
        #expect(snapshot.entries.count == (try WorkoutRepository.allExercises(context).count))
        #expect(snapshot.entries.map(\.name) == snapshot.entries.map(\.name).sorted())
    }

    @Test func emptyPlaceholderIsNotLoaded() {
        #expect(!ExerciseCatalogSnapshot.empty.isLoaded)
        #expect(ExerciseCatalogSnapshot.empty.entries.isEmpty)
    }

    @Test func entryFacetsMatchTheModel() throws {
        let bench = try #require(try WorkoutRepository.allExercises(context).first { $0.name == "Bench Press" })
        let entry = ExerciseCatalogEntry(exercise: bench)
        #expect(entry.id == bench.id)
        #expect(entry.searchKeywords == bench.searchKeywords)
        #expect(entry.primaryMuscleGroups == bench.primaryMuscleGroups)
        #expect(entry.trainedMuscleGroups == bench.trainedMuscleGroups)
        #expect(entry.equipmentValue == bench.equipmentValue)
        #expect(entry.category == (bench.categoryValue ?? .other))
        #expect(entry.summaryMuscleGroups.count <= 3)
    }

    @Test func categorySectionsCoverEveryEntryOnce() throws {
        let snapshot = try ExerciseCatalogSnapshot.build(in: context)
        let flattened = snapshot.categorySections.flatMap(\.entries)
        #expect(flattened.count == snapshot.entries.count)
        #expect(Set(flattened.map(\.id)) == Set(snapshot.entries.map(\.id)))
        for section in snapshot.categorySections {
            #expect(section.entries.allSatisfy { $0.category == section.category })
            #expect(section.entries.map(\.name) == section.entries.map(\.name).sorted())
        }
    }

    @Test func groupListIsAlphabeticalAndOnlyThatGroup() throws {
        let snapshot = try ExerciseCatalogSnapshot.build(in: context)
        let chest = snapshot.entries(in: .chest)
        #expect(!chest.isEmpty)
        #expect(chest.allSatisfy { $0.trainedMuscleGroups.contains(.chest) })
        let names = chest.map(\.name)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        #expect(Set(names) == Set(snapshot.facets.exercises(for: .chest).map(\.name)))
    }

    @Test func popularResolvesAgainstTheStoredCatalog() throws {
        let snapshot = try ExerciseCatalogSnapshot.build(in: context)
        #expect(!snapshot.popular.isEmpty)
        #expect(snapshot.popular.first?.name == "Bench Press")
    }

    @Test func searchRanksAndCaps() throws {
        let snapshot = try ExerciseCatalogSnapshot.build(in: context)
        let results = snapshot.search("bench", limit: 8)
        #expect(!results.isEmpty)
        #expect(results.count <= 8)
        #expect(results[0].name.localizedCaseInsensitiveContains("bench"))
        #expect(snapshot.search("   ", limit: 8).isEmpty)
        #expect(snapshot.search("bench", limit: 0).isEmpty)
    }

    @Test func watchSearchLimitSurfacesNonPrefixKeywordMatches() throws {
        let snapshot = try ExerciseCatalogSnapshot.build(in: context)
        let results = snapshot.search("incline", limit: WatchExerciseSearchPresenter.resultLimit)
        #expect(results.contains { !$0.name.lowercased().hasPrefix("incline") },
                      "keyword search must reach names where the term is not first")
    }

    @Test func recentIsNewestFirstAndLimited() throws {
        let all = try WorkoutRepository.allExercises(context)
        let pushdown = try #require(all.first { $0.name == "Triceps Pushdown" })
        let bench = try #require(all.first { $0.name == "Bench Press" })
        let session = try WorkoutRepository.createSession(in: context)
        let start = Date(timeIntervalSince1970: 1_000)
        try WorkoutRepository.addSet(to: session, exercise: pushdown, weightKg: 30, reps: 12,
                                     completedAt: start, in: context)
        try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5,
                                     completedAt: start.addingTimeInterval(60), in: context)
        try context.save()

        let snapshot = try ExerciseCatalogSnapshot.build(in: context, recentLimit: 12)
        #expect(snapshot.recent.map(\.name) == ["Bench Press", "Triceps Pushdown"])
        #expect(try ExerciseCatalogSnapshot.build(in: context, recentLimit: 1).recent.map(\.name) ==
                       ["Bench Press"])
        #expect(try ExerciseCatalogSnapshot.build(in: context, recentLimit: 0).recent.isEmpty)
    }

    @Test func customExerciseEntry() throws {
        let custom = Exercise(name: "Cable Y Raise", isCustom: true, primaryMuscles: ["deltoids"])
        context.insert(custom)
        try context.save()
        let entry = try #require(try ExerciseCatalogSnapshot.build(in: context).entries.first { $0.name == "Cable Y Raise" })
        #expect(entry.isCustom)
        #expect(entry.category == .other)
        #expect(entry.summaryMuscleGroups == MuscleGroup.canonicalize(["deltoids"]))
    }

    @Test func exerciseByIDResolvesTheLiveModel() throws {
        let bench = try #require(try WorkoutRepository.allExercises(context).first { $0.name == "Bench Press" })
        #expect(ExerciseCatalogSnapshot.exercise(id: bench.id, in: context)?.name == "Bench Press")
        #expect(ExerciseCatalogSnapshot.exercise(id: UUID(), in: context) == nil)
    }

    @Test func changeSignalIsTheMostRecentlyEditedExercise() throws {
        let edited = try #require(try WorkoutRepository.allExercises(context).first)
        edited.updatedAt = Date().addingTimeInterval(3_600)
        try context.save()
        let newest = try context.fetch(ExerciseCatalogSnapshot.changeSignalDescriptor)
        #expect(newest.map(\.id) == [edited.id])
    }

    @Test func loadBuildsOnABackgroundContext() async throws {
        let container = try #require(self.container)
        let snapshot = await ExerciseCatalogSnapshot.load(from: container, recentLimit: 5)
        #expect(snapshot.isLoaded)
        #expect(snapshot.entries.count == ExerciseLibrary.starter.count)
    }

    @Test func swapPresenterPreparesEveryOtherExercise() async throws {
        let bench = try #require(try WorkoutRepository.allExercises(context).first { $0.name == "Bench Press" })
        let source = ExerciseSwapCandidates.prepared(bench)
        #expect(source.id == bench.id.uuidString)
        #expect(!source.direct.isEmpty)
        let container = try #require(self.container)
        let presenter = await ExerciseSwapCandidates.presenter(source: source, container: container)
        #expect(presenter.candidates.count == ExerciseLibrary.starter.count - 1)
        #expect(!presenter.candidates.contains { $0.id == source.id })
        #expect(!presenter.results(for: presenter.defaultType).isEmpty)
    }
}

/// The Watch resolves exercises by exact name with a one-row fetch instead of
/// loading the whole catalog on the first lookup of every workout.
final class WatchStrengthFlowExerciseLookupTests {
    private var container: ModelContainer!
    private var context: ModelContext!

    init() throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    deinit {
        context = nil
        container = nil
    }

    @Test func exactNameUsesTheStoredExerciseWithoutCreatingOne() throws {
        let before = try WorkoutRepository.allExercises(context).count
        let model = WatchStrengthFlowModel(context: context)
        model.start()
        model.addExercise(named: "Bench Press")
        #expect(try WorkoutRepository.allExercises(context).count == before)
        #expect(model.exerciseList.map(\.exercise.name) == ["Bench Press"])
    }

    @Test func differentCaseStillResolvesTheBuiltIn() throws {
        let before = try WorkoutRepository.allExercises(context).count
        let model = WatchStrengthFlowModel(context: context)
        model.start()
        model.addExercise(named: "bench press")
        #expect(try WorkoutRepository.allExercises(context).count == before)
        #expect(model.exerciseList.map(\.exercise.name) == ["Bench Press"])
    }
}
#endif
