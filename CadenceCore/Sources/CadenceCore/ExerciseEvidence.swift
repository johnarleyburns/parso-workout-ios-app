import Foundation

/// The literature behind free-exercise-db++'s muscle-role annotations.
public enum ExerciseEvidence {
    public struct PatternEvidence: Equatable, Sendable, Identifiable {
        public let id: String
        public let displayName: String
        public let status: String
        public let summary: String
        public let citationIDs: [String]
    }

    private static let sourceLabels: [String: String] = [
        "systematic_review": String(localized: "Systematic review", bundle: .module),
        "experimental": String(localized: "Experimental study", bundle: .module),
        "meta_regression": String(localized: "Meta-regression", bundle: .module),
        "review_or_position": String(localized: "Review / position statement", bundle: .module),
        "training_intervention": String(localized: "Training intervention", bundle: .module),
        "randomized_controlled_trial": String(localized: "Randomized controlled trial", bundle: .module),
    ]

    public static let patterns: [String: PatternEvidence] = TrainingEngineBridge.evidencePatterns
        .mapValues { pattern in PatternEvidence(
            id: "", displayName: "", status: pattern.status, summary: pattern.summary,
            citationIDs: pattern.references.map { "exdb.\($0)" }
        ) }
        .reduce(into: [:]) { result, entry in
            result[entry.key] = PatternEvidence(
                id: entry.key, displayName: displayName(for: entry.key),
                status: entry.value.status, summary: entry.value.summary,
                citationIDs: entry.value.citationIDs
            )
        }

    public static let citations: [Citation] = TrainingEngineBridge.evidenceReferences
        .sorted { $0.key < $1.key }
        .map { id, reference in
            let year = Int(String(id.suffix(4))) ?? 0
            return Citation(
                id: "exdb.\(id)", authors: "", year: year,
                title: reference.title,
                source: sourceLabels[reference.type] ?? reference.type.replacingOccurrences(of: "_", with: " ").capitalized,
                url: reference.url
            )
        }

    public static let citationsByID: [String: Citation] = Dictionary(uniqueKeysWithValues: citations.map { ($0.id, $0) })

    public static func evidence(forPatternIDs ids: [String]) -> [PatternEvidence] {
        ids.compactMap { patterns[$0] }
    }

    private static func displayName(for id: String) -> String {
        let overrides = [
            "kettlebell_figure8": String(localized: "Kettlebell Figure 8", bundle: .module),
            "olympic_clean_and_jerk": String(localized: "Olympic Clean and Jerk", bundle: .module),
            "horizontal_press_triceps_bias": String(localized: "Horizontal Press (Triceps Bias)", bundle: .module),
            "elbow_flexion_brachioradialis_bias": String(localized: "Elbow Flexion (Brachioradialis Bias)", bundle: .module),
            "dip_chest_bias": String(localized: "Dip (Chest Bias)", bundle: .module), "dip_triceps_bias": String(localized: "Dip (Triceps Bias)", bundle: .module),
            "squat_quad_bias": String(localized: "Squat (Quad Bias)", bundle: .module),
            "plantar_flexion_straight_knee": String(localized: "Plantar Flexion (Straight Knee)", bundle: .module),
            "plantar_flexion_bent_knee": String(localized: "Plantar Flexion (Bent Knee)", bundle: .module),
        ]
        if let override = overrides[id] { return override }
        return id.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
}
