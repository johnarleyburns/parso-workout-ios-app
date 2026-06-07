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
    public static func rank<T: ExerciseSearchable>(_ query: String, over candidates: [T]) -> [T] {
        let terms = normalize(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else {
            return candidates.sorted { lhs, rhs in
                if lhs.isCustom != rhs.isCustom { return !lhs.isCustom }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
        let scored: [(T, Int)] = candidates.compactMap { c in
            let nameNorm = normalize(c.name)
            let keys = c.searchKeywords.map(normalize)
            var total = 0
            for term in terms {
                let s = termScore(term, name: nameNorm, keywords: keys)
                if s == 0 { return nil }          // every term must match
                total += s
            }
            return (c, total)
        }
        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.0.isCustom != b.0.isCustom { return !a.0.isCustom }
            return a.0.name.localizedCaseInsensitiveCompare(b.0.name) == .orderedAscending
        }.map(\.0)
    }

    // MARK: Scoring

    private static func termScore(_ term: String, name: String, keywords: [String]) -> Int {
        if name.hasPrefix(term) { return 4 }
        if name.contains(term) { return 3 }
        if keywords.contains(term) { return 2 }
        if keywords.contains(where: { $0.hasPrefix(term) }) { return 1 }
        return 0
    }

    /// Lowercased, diacritic-folded, whitespace-collapsed.
    public static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

extension Exercise: ExerciseSearchable {}

