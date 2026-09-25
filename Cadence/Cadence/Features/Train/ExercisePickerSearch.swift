import Foundation
import SwiftData
import CadenceCore
import CadenceFeatures

/// Everything the exercise picker derives from a query, computed ONCE per
/// debounced keystroke instead of once per SwiftUI body evaluation.
///
/// Field test 2026-08-19 #4: typing in the picker had become "several seconds of
/// delay per key". The cause was not the ranking — that already runs off a
/// prebuilt `ExerciseSearchIndex` — but the three sibling computed properties
/// around it (`filtered`, `exactMatchExists`, `bestLibraryMatch`, `popular`).
/// Each walked the full `@Query` array of `@Model` rows, folding and comparing
/// names, and each was re-evaluated on *every* redraw of the view — and the view
/// redraws whenever its presenting session redraws, which during a live workout
/// is once a second. Snapshotting the answer into `@State` makes a keystroke one
/// pass over pre-normalized strings and a redraw free.
///
/// The indexes themselves are now built from an `ExerciseCatalogSnapshot` on a
/// background context. Building them from `@Model` rows on the main actor
/// (three indexes, each decoding every row's stored muscle and keyword lists)
/// was what froze the sheet as it opened.
struct ExercisePickerSearch: Sendable {

    struct Outcome: Equatable, Sendable {
        var query: String = ""
        var results: [ExerciseCatalogEntry] = []
        /// A catalog entry already carries this exact name — suppresses "Create …".
        var exactMatch: Bool = false
        /// A near-miss built-in worth offering instead of creating a duplicate.
        var bestMatch: ExerciseCatalogEntry?

        static var empty: Outcome { Outcome() }
    }

    let catalog: ExerciseCatalogSnapshot
    private let libraryIndex: ExerciseSearchIndex<ExerciseCatalogEntry>
    private let normalizedNameByID: [UUID: String]
    private let builtInNames: Set<String>
    private let customNames: Set<String>

    static let empty = ExercisePickerSearch(catalog: .empty)

    init(catalog: ExerciseCatalogSnapshot) {
        self.catalog = catalog
        let names = catalog.searchIndex.normalizedNames
        normalizedNameByID = Dictionary(names.map { ($0.item.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        builtInNames = Set(names.lazy.filter { !$0.isCustom }.map { $0.name })
        customNames = Set(names.lazy.filter { $0.isCustom }.map { $0.name })
        libraryIndex = ExerciseSearchIndex(catalog.entries.filter { !$0.isCustom })
    }

    /// Reads the catalog and builds every index on a background context.
    static func load(from container: ModelContainer) async -> ExercisePickerSearch {
        let catalog = await ExerciseCatalogSnapshot.load(from: container)
        return await Task.detached(priority: .userInitiated) {
            ExercisePickerSearch(catalog: catalog)
        }.value
    }

    /// The curated "Popular" list, resolved against the catalog once per load.
    var popular: [ExerciseCatalogEntry] { catalog.popular }

    func outcome(for rawQuery: String) -> Outcome {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        let normalized = ExerciseSearch.normalize(trimmed)
        let primaryGroup = ExerciseSearch.primaryMuscleGroup(matching: trimmed)
        var outcome = Outcome(query: trimmed,
                              results: catalog.searchIndex.rank(trimmed,
                                                                prioritizingPrimaryMuscle: primaryGroup))
        // A muscle-group query is a primary-muscle request. Ranking alone is not
        // enough: secondary-only exercises must not appear as solutions to a
        // volume gap.
        if let primaryGroup {
            outcome.results = outcome.results.filter {
                $0.primaryMuscleGroups.contains(primaryGroup)
            }
        }
        outcome.exactMatch = builtInNames.contains(normalized) || customNames.contains(normalized)
        outcome.bestMatch = bestLibraryMatch(normalized: normalized, query: trimmed)
        return outcome
    }

    /// A built-in whose name overlaps the query without being it — "found a good
    /// match" rather than letting the user create a near-duplicate. One pass over
    /// the pre-normalized names — no folding on the keystroke path.
    private func bestLibraryMatch(normalized: String, query: String) -> ExerciseCatalogEntry? {
        guard normalized.count >= 3 else { return nil }
        let ranked = libraryIndex.rank(query)
        var match: ExerciseCatalogEntry?
        var matchCount = 0
        for item in ranked {
            guard let name = normalizedNameByID[item.id], name != normalized else { continue }
            guard name.contains(normalized) || normalized.contains(name) else { continue }
            match = item
            matchCount += 1
            if matchCount > 1 { break }
        }
        return match
    }
}
