import Foundation
import SwiftData
import CadenceCore

/// One exercise as the pickers need it: plain values, read once.
///
/// The Watch Add Exercise screen and the iPhone picker used to work straight
/// off a `@Query` of every `Exercise` (~900 rows) on the main actor. Each
/// muscle, keyword, and equipment facet on the model decodes a stored string
/// every time it is read, and the pickers read them thousands of times per
/// open (index builds, group lists, per-render grouping), so opening or
/// scrolling a picker blocked the UI. This copies the facets once, on a
/// background context, into a value the UI can index and render freely.
public struct ExerciseCatalogEntry: Sendable, Hashable, Identifiable, ExerciseSearchable, EquipmentClassifiable {
    public let id: UUID
    public let name: String
    public let searchKeywords: [String]
    public let isCustom: Bool
    public let primaryMuscleGroups: [MuscleGroup]
    public let trainedMuscleGroups: Set<MuscleGroup>
    public let equipmentValue: Equipment?
    public let category: ExerciseCategory
    /// Up to three groups for a row subtitle: the primary muscles, or the
    /// legacy muscle tags when a row has no primary muscles.
    public let summaryMuscleGroups: [MuscleGroup]

    public init(id: UUID, name: String, searchKeywords: [String] = [], isCustom: Bool = false,
                primaryMuscleGroups: [MuscleGroup] = [], trainedMuscleGroups: Set<MuscleGroup> = [],
                equipmentValue: Equipment? = nil, category: ExerciseCategory = .other,
                summaryMuscleGroups: [MuscleGroup] = []) {
        self.id = id
        self.name = name
        self.searchKeywords = searchKeywords
        self.isCustom = isCustom
        self.primaryMuscleGroups = primaryMuscleGroups
        self.trainedMuscleGroups = trainedMuscleGroups
        self.equipmentValue = equipmentValue
        self.category = category
        self.summaryMuscleGroups = summaryMuscleGroups
    }

    /// Reads every facet the pickers use exactly once. Call it in the model's
    /// own context.
    public init(exercise: Exercise) {
        let primary = exercise.primaryMuscles
        self.init(id: exercise.id,
                  name: exercise.name,
                  searchKeywords: exercise.searchKeywords,
                  isCustom: exercise.isCustom,
                  primaryMuscleGroups: MuscleGroup.canonicalize(primary),
                  trainedMuscleGroups: exercise.trainedMuscleGroups,
                  equipmentValue: exercise.equipmentValue,
                  category: exercise.categoryValue ?? .other,
                  summaryMuscleGroups: Array(MuscleGroup.canonicalize(
                      primary.isEmpty ? exercise.muscleGroups : primary).prefix(3)))
    }
}

/// Everything the exercise pickers derive from the catalog, built once off the
/// main actor. Views hold this value, render entries, and resolve the
/// `Exercise` model by id only when the user picks one.
public struct ExerciseCatalogSnapshot: Sendable {
    public struct CategorySection: Sendable, Identifiable {
        public let category: ExerciseCategory
        public let entries: [ExerciseCatalogEntry]
        public var id: ExerciseCategory { category }
    }

    /// Every exercise, in name order.
    public let entries: [ExerciseCatalogEntry]
    /// Most recently logged exercises, newest first.
    public let recent: [ExerciseCatalogEntry]
    /// The curated popular shortlist resolved against the stored catalog.
    public let popular: [ExerciseCatalogEntry]
    /// All exercises grouped by category (category order, name order within).
    public let categorySections: [CategorySection]
    public let facets: ExerciseFacetIndex<ExerciseCatalogEntry>
    public let searchIndex: ExerciseSearchIndex<ExerciseCatalogEntry>
    /// False only for the placeholder shown before the first load finishes.
    public let isLoaded: Bool
    private let groupLists: [MuscleGroup: [ExerciseCatalogEntry]]

    public static let empty = ExerciseCatalogSnapshot(entries: [], recent: [], isLoaded: false)

    public init(entries: [ExerciseCatalogEntry], recent: [ExerciseCatalogEntry], isLoaded: Bool = true) {
        let sorted = entries.sorted { $0.name < $1.name }
        self.entries = sorted
        self.recent = recent
        self.isLoaded = isLoaded
        let index = ExerciseSearchIndex(sorted)
        self.searchIndex = index
        let facets = ExerciseFacetIndex(sorted)
        self.facets = facets

        var byNormalizedName: [String: ExerciseCatalogEntry] = [:]
        for row in index.normalizedNames where byNormalizedName[row.name] == nil {
            byNormalizedName[row.name] = row.item
        }
        self.popular = ExerciseLibrary.popularNames.compactMap { byNormalizedName[ExerciseSearch.normalize($0)] }

        let byCategory = Dictionary(grouping: sorted, by: \.category)
        self.categorySections = ExerciseCategory.allCases.compactMap { category in
            guard let items = byCategory[category], !items.isEmpty else { return nil }
            return CategorySection(category: category, entries: items)
        }

        var lists: [MuscleGroup: [ExerciseCatalogEntry]] = [:]
        for (group, items) in facets.byGroup {
            lists[group] = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        self.groupLists = lists
    }

    /// Every exercise training `group`, alphabetical ignoring case (the Watch
    /// category list).
    public func entries(in group: MuscleGroup) -> [ExerciseCatalogEntry] {
        groupLists[group] ?? []
    }

    /// Ranked search, capped to `limit` results.
    public func search(_ query: String, limit: Int) -> [ExerciseCatalogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }
        return Array(searchIndex.rank(trimmed).prefix(limit))
    }

    /// Builds the snapshot from `context`. Run it on a background context; it
    /// reads every stored exercise once.
    public static func build(in context: ModelContext, recentLimit: Int = 25) throws -> ExerciseCatalogSnapshot {
        let exercises = try WorkoutRepository.allExercises(context)
        let entries = exercises.map(ExerciseCatalogEntry.init(exercise:))
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = recentLimit > 0
            ? try WorkoutRepository.recentlyUsedExercises(context, limit: recentLimit).compactMap { byID[$0.id] }
            : []
        return ExerciseCatalogSnapshot(entries: entries, recent: recent)
    }

    /// Builds the snapshot on a background context and returns it. A failed
    /// read returns an empty, loaded catalog, so the UI shows "no matches"
    /// rather than loading forever.
    public static func load(from container: ModelContainer, recentLimit: Int = 25) async -> ExerciseCatalogSnapshot {
        await Task.detached(priority: .userInitiated) {
            (try? ExerciseCatalogSnapshot.build(in: ModelContext(container), recentLimit: recentLimit))
                ?? ExerciseCatalogSnapshot(entries: [], recent: [])
        }.value
    }

    /// The live model for a picked entry, from the caller's context. One row,
    /// by id.
    public static func exercise(id: UUID, in context: ModelContext) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The most recently edited exercise. A picker observes this one-row query
    /// instead of the whole catalog: it changes when rows are added or edited
    /// (seeding, sync, a new custom exercise), which is when the snapshot is
    /// rebuilt.
    public static var changeSignalDescriptor: FetchDescriptor<Exercise> {
        var descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }
}

/// Swap candidates, prepared off the main actor. The swap sheet used to
/// prepare all ~900 exercises and rank them several times per render.
public enum ExerciseSwapCandidates {
    /// DB++ roles when present, otherwise the catalog muscle lists.
    public static func prepared(_ exercise: Exercise) -> ExerciseSimilarity.Prepared {
        let direct = Set(exercise.directMuscles.isEmpty ? MuscleGroup.canonicalize(exercise.primaryMuscles) : exercise.directMuscles)
        let indirect = Set(exercise.indirectMuscles.isEmpty ? MuscleGroup.canonicalize(exercise.secondaryMuscles) : exercise.indirectMuscles)
        return ExerciseSimilarity.Prepared(id: exercise.id.uuidString, name: exercise.name, direct: direct, indirect: indirect,
                                           patterns: Set(exercise.movementPatternIDs), mechanics: exercise.mechanicsValue,
                                           force: exercise.forceValue, equipment: exercise.equipmentValue,
                                           modalities: Set(exercise.modalities), trainingTypes: Set(exercise.trainingTypes),
                                           volumeEligible: exercise.volumeEligible)
    }

    /// Prepares every stored exercise and builds the presenter on a background
    /// context.
    public static func presenter(source: ExerciseSimilarity.Prepared,
                                 container: ModelContainer) async -> ExerciseSwapPresenter {
        await Task.detached(priority: .userInitiated) {
            let exercises = (try? WorkoutRepository.allExercises(ModelContext(container))) ?? []
            return ExerciseSwapPresenter(source: source, candidates: exercises.map(ExerciseSwapCandidates.prepared))
        }.value
    }
}
