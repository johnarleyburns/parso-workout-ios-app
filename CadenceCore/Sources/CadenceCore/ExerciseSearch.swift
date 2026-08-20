import Foundation

/// Anything rankable by `ExerciseSearch` (field-testing §03). Both the seeded
/// catalog and the SwiftData `Exercise` conform.
public protocol ExerciseSearchable {
    var name: String { get }
    var searchKeywords: [String] { get }
    var isCustom: Bool { get }
}

/// Ranked, keyword-aware exercise search. Pure and headless-testable; replaces
/// the old name-substring filter so "cable" surfaces all cable movements and
/// "lats"/"pecs" resolve via muscle synonyms.
public enum ExerciseSearch {

    /// Builds the flattened, lowercased keyword set for an exercise from its
    /// facets (decision #12). Stored on the model so search is a token compare.
    public static func keywords(name: String,
                                equipment: Equipment?,
                                isLateral: Bool,
                                force: Force?,
                                mechanics: Mechanics?,
                                primaryMuscles: [String],
                                secondaryMuscles: [String]) -> [String] {
        var tokens: Set<String> = []
        for word in normalize(name).split(separator: " ") { tokens.insert(String(word)) }
        if let equipment { tokens.insert(equipment.rawValue) }
        if isLateral { ["isolateral", "unilateral", "single arm", "single leg"].forEach { tokens.insert($0) } }
        if let force { tokens.insert(force.rawValue) }
        if let mechanics { tokens.insert(mechanics.rawValue) }
        for m in primaryMuscles + secondaryMuscles {
            MuscleCatalog.searchTerms(for: m).forEach { tokens.insert(normalize($0)) }
        }
        return tokens.filter { !$0.isEmpty }.sorted()
    }

    /// Ranks candidates for a query. Empty query returns all (built-ins first,
    /// then alphabetical). Multi-word queries require every term to match some
    /// facet (AND across terms).
    ///
    /// Convenience wrapper — normalizes every candidate on each call, so it is
    /// O(candidates × keywords) per invocation. For interactive, per-keystroke
    /// search over a large catalog build an `ExerciseSearchIndex` once and reuse
    /// it (that precomputes the normalization); this stays for one-shot callers
    /// and tests.
    public static func rank<T: ExerciseSearchable>(_ query: String, over candidates: [T]) -> [T] {
        ExerciseSearchIndex(candidates).rank(query)
    }

    // MARK: Scoring

    static func termScore(_ term: String, name: String, keywords: [String]) -> Int {
        if name.hasPrefix(term) { return 4 }
        if name.contains(term) { return 3 }
        if keywords.contains(term) { return 2 }
        if keywords.contains(where: { $0.hasPrefix(term) }) { return 1 }
        return 0
    }

    /// Splits a query into normalized, non-empty terms.
    static func terms(_ query: String) -> [String] {
        normalize(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    /// Lowercased, diacritic-folded, whitespace-collapsed. Regex-free — the old
    /// `\s+` regular expression was the dominant cost when normalizing thousands
    /// of strings per keystroke.
    public static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

/// A precomputed, reusable search index. Normalizing each exercise's name and
/// keywords is done **once** at construction, so per-keystroke `rank` is a cheap
/// prefix/contains scan over already-normalized strings — no diacritic folding,
/// no keyword decoding, no regex on the hot path. Build it once from the loaded
/// catalog and reuse across keystrokes (fixes the "extremely slow/jerky" search).
public struct ExerciseSearchIndex<T: ExerciseSearchable> {
    private struct Indexed {
        let item: T
        let name: String
        let keywords: [String]
        let isCustom: Bool
    }

    private let indexed: [Indexed]

    public init(_ items: [T]) {
        indexed = items.map { item in
            Indexed(item: item,
                    name: ExerciseSearch.normalize(item.name),
                    keywords: item.searchKeywords.map(ExerciseSearch.normalize),
                    isCustom: item.isCustom)
        }
    }

    public var count: Int { indexed.count }

    /// Every candidate's already-normalized name, in index order — lets a caller
    /// scan for exact/substring matches without re-folding thousands of `@Model`
    /// name strings on the keystroke path (field test 2026-08-19 #4).
    public var normalizedNames: [(item: T, name: String, isCustom: Bool)] {
        indexed.map { ($0.item, $0.name, $0.isCustom) }
    }

    public func rank(_ query: String) -> [T] {
        let terms = ExerciseSearch.terms(query)
        guard !terms.isEmpty else {
            return indexed.sorted(by: Self.alphabeticalBuiltInsFirst).map(\.item)
        }
        let scored: [(Indexed, Int)] = indexed.compactMap { entry in
            var total = 0
            for term in terms {
                let s = ExerciseSearch.termScore(term, name: entry.name, keywords: entry.keywords)
                if s == 0 { return nil }          // every term must match (AND)
                total += s
            }
            return (entry, total)
        }
        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return Self.alphabeticalBuiltInsFirst(a.0, b.0)
        }.map(\.0.item)
    }

    /// Tie-break on the PRE-normalized name. Reading `item.name` here meant a
    /// SwiftData property access (and, inside a SwiftUI body, an observation
    /// registration) for every comparison in every sort — the dominant cost once
    /// the catalog grew (field test 2026-08-19 #4).
    private static func alphabeticalBuiltInsFirst(_ lhs: Indexed, _ rhs: Indexed) -> Bool {
        if lhs.isCustom != rhs.isCustom { return !lhs.isCustom }
        return lhs.name < rhs.name
    }
}

extension Exercise: ExerciseSearchable {}
