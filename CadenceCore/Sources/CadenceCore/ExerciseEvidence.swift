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
        "systematic_review": "Systematic review",
        "experimental": "Experimental study",
        "meta_regression": "Meta-regression",
        "review_or_position": "Review / position statement",
        "training_intervention": "Training intervention",
        "randomized_controlled_trial": "Randomized controlled trial",
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
            "kettlebell_figure8": "Kettlebell Figure 8",
            "olympic_clean_and_jerk": "Olympic Clean and Jerk",
            "horizontal_press_triceps_bias": "Horizontal Press (Triceps Bias)",
            "elbow_flexion_brachioradialis_bias": "Elbow Flexion (Brachioradialis Bias)",
            "dip_chest_bias": "Dip (Chest Bias)", "dip_triceps_bias": "Dip (Triceps Bias)",
            "squat_quad_bias": "Squat (Quad Bias)",
            "plantar_flexion_straight_knee": "Plantar Flexion (Straight Knee)",
            "plantar_flexion_bent_knee": "Plantar Flexion (Bent Knee)",
        ]
        if let override = overrides[id] { return override }
        return id.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
}
