import Foundation
import CadenceCore

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
struct ExercisePickerSearch {

    struct Outcome: Equatable {
        var query: String = ""
        var results: [Exercise] = []
        /// A catalog entry already carries this exact name — suppresses "Create …".
        var exactMatch: Bool = false
        /// A near-miss built-in worth offering instead of creating a duplicate.
        var bestMatch: Exercise?

        static var empty: Outcome { Outcome() }

        static func == (lhs: Outcome, rhs: Outcome) -> Bool {
            lhs.query == rhs.query
                && lhs.exactMatch == rhs.exactMatch
                && lhs.bestMatch?.id == rhs.bestMatch?.id
                && lhs.results.map(\.id) == rhs.results.map(\.id)
        }
    }

    private var index = ExerciseSearchIndex<Exercise>([])
    /// `(exercise, normalized name, isCustom)` — folded once at build time.
    private var names: [(item: Exercise, name: String, isCustom: Bool)] = []
    private var popularCache: [Exercise] = []
    private(set) var indexedCount = -1

    /// Rebuilds when the catalog size changes. Cheap to call speculatively.
    mutating func rebuildIfNeeded(_ exercises: [Exercise]) -> Bool {
        guard exercises.count != indexedCount else { return false }
        index = ExerciseSearchIndex(exercises)
        names = index.normalizedNames
        indexedCount = exercises.count
        let byName = Dictionary(names.map { ($0.name, $0.item) }, uniquingKeysWith: { first, _ in first })
        popularCache = ExerciseLibrary.popularNames.compactMap { byName[ExerciseSearch.normalize($0)] }
        return true
    }

    /// The curated "Popular" list, resolved against the catalog once per rebuild.
    var popular: [Exercise] { popularCache }

    func outcome(for rawQuery: String) -> Outcome {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        let normalized = ExerciseSearch.normalize(trimmed)
        var outcome = Outcome(query: trimmed, results: index.rank(trimmed))
        outcome.exactMatch = names.contains { $0.name == normalized }
        outcome.bestMatch = bestLibraryMatch(normalized: normalized, query: trimmed)
        return outcome
    }

    /// A built-in whose name overlaps the query without being it — "found a good
    /// match" rather than letting the user create a near-duplicate. One pass over
    /// the pre-normalized names — no folding on the keystroke path.
    private func bestLibraryMatch(normalized: String, query: String) -> Exercise? {
        guard normalized.count >= 3 else { return nil }
        var matches: [Exercise] = []
        for entry in names where !entry.isCustom && entry.name != normalized {
            if entry.name.contains(normalized) || normalized.contains(entry.name) {
                matches.append(entry.item)
            }
        }
        if matches.count == 1 { return matches[0] }
        guard matches.count > 1 else { return nil }
        return ExerciseSearchIndex(matches).rank(query).first
    }
}
