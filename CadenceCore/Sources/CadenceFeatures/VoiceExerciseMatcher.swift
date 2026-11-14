import Foundation

/// Outcome of matching a spoken exercise term against a workout's exercise names.
public enum VoiceExerciseMatch: Equatable, Sendable {
    /// Normalized names are identical.
    case exact(String)
    /// A unique prefix or one-error near match; callers should require review.
    case inferred(String)
    /// Several candidates are plausible; nothing is selected.
    case ambiguous([String])
    case none

    /// The selected candidate, if any.
    public var selected: String? {
        switch self {
        case .exact(let name), .inferred(let name): return name
        case .ambiguous, .none: return nil
        }
    }

    /// True when the match was not exact and should be reviewed by the user.
    public var isInferred: Bool {
        if case .inferred = self { return true }
        return false
    }
}

/// Pure, deterministic, conservative matcher for spoken exercise names.
public enum VoiceExerciseMatcher {
    /// Minimum length of a term/token eligible for one-error near matching.
    static let minimumNearLength = 4

    public static func match(_ term: String, candidates: [String]) -> VoiceExerciseMatch {
        let query = normalize(term)
        guard !query.isEmpty else { return .none }
        // Sorted so results never depend on input order.
        let entries = Set(candidates).sorted().map { (name: $0, norm: normalize($0)) }
            .filter { !$0.norm.isEmpty }

        if let exact = entries.first(where: { $0.norm == query }) { return .exact(exact.name) }

        let prefix = entries.filter { $0.norm.hasPrefix(query) || query.hasPrefix($0.norm) }
        if prefix.count == 1 { return .inferred(prefix[0].name) }
        if prefix.count > 1 { return .ambiguous(prefix.map(\.name)) }

        guard query.count >= minimumNearLength else { return .none }
        let scored: [(name: String, distance: Int)] = entries.compactMap { entry in
            guard let d = nearDistance(query, entry.norm) else { return nil }
            return (entry.name, d)
        }
        guard let best = scored.map(\.distance).min() else { return .none }
        let top = scored.filter { $0.distance == best }
        return top.count == 1 ? .inferred(top[0].name) : .ambiguous(top.map(\.name))
    }

    /// Best edit distance (<= 1) between the query and the whole name or a
    /// same-length window of its tokens; nil when nothing is close enough.
    private static func nearDistance(_ query: String, _ name: String) -> Int? {
        let tokens = name.split(separator: " ").map(String.init)
        let width = query.split(separator: " ").count
        var pieces = [name]
        if width <= tokens.count {
            for start in 0...(tokens.count - width) {
                pieces.append(tokens[start..<(start + width)].joined(separator: " "))
            }
        }
        let distances = pieces.filter { $0.count >= minimumNearLength }
            .map { editDistance(query, $0) }
            .filter { $0 <= 1 }
        return distances.min()
    }

    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let mapped = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }

    /// Levenshtein distance.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[y.count]
    }
}
