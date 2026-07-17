import Foundation

/// Ranks substitute exercises for a given exercise based on shared movement
/// pattern/family, primary body parts, equipment compatibility, and recency.
///
/// Pure engine — headless-testable under `swift test`. Both the watch's smart
/// swap screen and the phone's `ExercisePickerView` swap mode use the same ranker.
public enum ExerciseSubstitution {

    public struct Candidate: Equatable, Sendable {
        public let name: String
        public let score: Int
        public let reasons: [String]

        public init(name: String, score: Int, reasons: [String]) {
            self.name = name
            self.score = score
            self.reasons = reasons
        }
    }

    /// Details about the exercise being swapped *from*. Callers pass whatever they
    /// have; nil fields are simply not scored.
    public struct Source: Equatable, Sendable {
        public var name: String
        public var category: String?    // rawValue of ExerciseCategory
        public var primaryMuscles: [String]?
        public var equipment: String?
        public var movementPattern: String?

        public init(name: String, category: String? = nil,
                    primaryMuscles: [String]? = nil, equipment: String? = nil,
                    movementPattern: String? = nil) {
            self.name = name
            self.category = category
            self.primaryMuscles = primaryMuscles
            self.equipment = equipment
            self.movementPattern = movementPattern
        }
    }

    /// Ranks `candidates` (exercise names) against the source, returning the top
    /// `limit` (default 6) sorted by score descending. The source exercise itself
    /// is excluded.
    ///
    /// Scoring:
    ///  - +30 same movement pattern
    ///  - +15 same category
    ///  - +10 per shared primary muscle (up to 30)
    ///  - +10 same equipment
    ///  - +20 recent (passed as a set of recently-used names)
    ///  - -100 if same name as source (excluded)
    public static func rank(source: Source,
                            candidates: [String],
                            recents: Set<String> = [],
                            limit: Int = 6) -> [Candidate] {
        var results: [Candidate] = []

        for name in candidates {
            guard name != source.name else { continue }

            var score = 0
            var reasons: [String] = []

            // Movement pattern match: highest-value signal
            if let pattern = source.movementPattern,
               movementPattern(of: name) == pattern {
                score += 30
                reasons.append("Same movement: \(pattern)")
            }

            // Category match
            if let cat = source.category, category(of: name) == cat {
                score += 15
                reasons.append("Same category")
            }

            // Primary muscles overlap
            if let muscles = source.primaryMuscles {
                let targetMuscles = primaryMuscles(of: name)
                let overlap = muscles.filter { targetMuscles.contains($0) }
                if !overlap.isEmpty {
                    let muscleScore = min(30, overlap.count * 10)
                    score += muscleScore
                    reasons.append("Targets \(overlap.joined(separator: ", "))")
                }
            }

            // Equipment compatibility
            if let eq = source.equipment, equipment(of: name) == eq {
                score += 10
                reasons.append("Same equipment")
            }

            // Recency bonus
            if recents.contains(name) {
                score += 20
                reasons.append("Recent")
            }

            results.append(Candidate(name: name, score: score, reasons: reasons))
        }

        return results
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Knowledge base lookups (mock until integrated with ExerciseLibrary)

    private static func movementPattern(of name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("press") || lower.contains("push") { return "press" }
        if lower.contains("squat") || lower.contains("lunge") { return "squat" }
        if lower.contains("deadlift") || lower.contains("row") || lower.contains("pull") { return "pull" }
        if lower.contains("curl") { return "curl" }
        if lower.contains("extension") || lower.contains("tricep") { return "extension" }
        if lower.contains("raise") || lower.contains("fly") { return "raise" }
        if lower.contains("plank") || lower.contains("crunch") { return "core" }
        return "other"
    }

    private static func category(of name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("bench") || lower.contains("press") || lower.contains("fly")
            || lower.contains("tricep") || lower.contains("curl") { return "push" }
        if lower.contains("row") || lower.contains("pulldown") || lower.contains("pull")
            || lower.contains("deadlift") || lower.contains("curl") { return "pull" }
        if lower.contains("squat") || lower.contains("lunge") || lower.contains("leg")
            || lower.contains("calf") { return "legs" }
        if lower.contains("plank") || lower.contains("crunch") || lower.contains("ab") { return "core" }
        return "other"
    }

    private static func primaryMuscles(of name: String) -> [String] {
        let lower = name.lowercased()
        if lower.contains("bench") { return ["chest", "triceps", "shoulders"] }
        if lower.contains("squat") { return ["quads", "glutes", "hamstrings"] }
        if lower.contains("deadlift") { return ["hamstrings", "glutes", "back"] }
        if lower.contains("press") || lower.contains("shoulder") { return ["shoulders", "triceps"] }
        if lower.contains("row") || lower.contains("pulldown") { return ["back", "biceps"] }
        if lower.contains("curl") { return ["biceps"] }
        if lower.contains("tricep") || lower.contains("extension") { return ["triceps"] }
        if lower.contains("lunge") { return ["quads", "glutes"] }
        if lower.contains("fly") { return ["chest"] }
        if lower.contains("pull-up") || lower.contains("pullup") { return ["back", "biceps"] }
        if lower.contains("calf") { return ["calves"] }
        if lower.contains("leg press") { return ["quads", "glutes"] }
        if lower.contains("plank") || lower.contains("crunch") { return ["abs"] }
        return ["full body"]
    }

    private static func equipment(of name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("barbell") || lower.contains("bench") || lower.contains("squat")
            || lower.contains("deadlift") || lower.contains("press") { return "barbell" }
        if lower.contains("dumbbell") || lower.contains("curl") || lower.contains("fly")
            || lower.contains("raise") || lower.contains("lunge") || lower.contains("extension") { return "dumbbell" }
        if lower.contains("cable") || lower.contains("pulldown") || lower.contains("row") { return "cable" }
        if lower.contains("pull-up") || lower.contains("pullup") || lower.contains("plank") { return "bodyweight" }
        return "other"
    }
}
