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
        "systematic_review": {
            #if os(Linux)
            "Systematic review"
            #else
            String(localized: "Systematic review", bundle: .module)
            #endif
        }(),
        "experimental": {
            #if os(Linux)
            "Experimental study"
            #else
            String(localized: "Experimental study", bundle: .module)
            #endif
        }(),
        "meta_regression": {
            #if os(Linux)
            "Meta-regression"
            #else
            String(localized: "Meta-regression", bundle: .module)
            #endif
        }(),
        "review_or_position": {
            #if os(Linux)
            "Review / position statement"
            #else
            String(localized: "Review / position statement", bundle: .module)
            #endif
        }(),
        "training_intervention": {
            #if os(Linux)
            "Training intervention"
            #else
            String(localized: "Training intervention", bundle: .module)
            #endif
        }(),
        "randomized_controlled_trial": {
            #if os(Linux)
            "Randomized controlled trial"
            #else
            String(localized: "Randomized controlled trial", bundle: .module)
            #endif
        }(),
        "clinical_exercise_guide": {
            #if os(Linux)
            "Clinical exercise guide"
            #else
            String(localized: "Clinical exercise guide", bundle: .module)
            #endif
        }(),
        "manufacturer_exercise_guide": {
            #if os(Linux)
            "Equipment demonstration"
            #else
            String(localized: "Equipment demonstration", bundle: .module)
            #endif
        }(),
    ]

    public static let usageReasons: [String: String] = Dictionary(uniqueKeysWithValues:
        TrainingEngineBridge.evidenceReferences.compactMap { id, reference in
            reference.reason.map { ("exdb.\(id)", $0) }
        })

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
            "kettlebell_figure8": {
                #if os(Linux)
                "Kettlebell Figure 8"
                #else
                String(localized: "Kettlebell Figure 8", bundle: .module)
                #endif
            }(),
            "olympic_clean_and_jerk": {
                #if os(Linux)
                "Olympic Clean and Jerk"
                #else
                String(localized: "Olympic Clean and Jerk", bundle: .module)
                #endif
            }(),
            "horizontal_press_triceps_bias": {
                #if os(Linux)
                "Horizontal Press (Triceps Bias)"
                #else
                String(localized: "Horizontal Press (Triceps Bias)", bundle: .module)
                #endif
            }(),
            "elbow_flexion_brachioradialis_bias": {
                #if os(Linux)
                "Elbow Flexion (Brachioradialis Bias)"
                #else
                String(localized: "Elbow Flexion (Brachioradialis Bias)", bundle: .module)
                #endif
            }(),
            "dip_chest_bias": {
                #if os(Linux)
                "Dip (Chest Bias)"
                #else
                String(localized: "Dip (Chest Bias)", bundle: .module)
                #endif
            }(), "dip_triceps_bias": {
                #if os(Linux)
                "Dip (Triceps Bias)"
                #else
                String(localized: "Dip (Triceps Bias)", bundle: .module)
                #endif
            }(),
            "squat_quad_bias": {
                #if os(Linux)
                "Squat (Quad Bias)"
                #else
                String(localized: "Squat (Quad Bias)", bundle: .module)
                #endif
            }(),
            "plantar_flexion_straight_knee": {
                #if os(Linux)
                "Plantar Flexion (Straight Knee)"
                #else
                String(localized: "Plantar Flexion (Straight Knee)", bundle: .module)
                #endif
            }(),
            "plantar_flexion_bent_knee": {
                #if os(Linux)
                "Plantar Flexion (Bent Knee)"
                #else
                String(localized: "Plantar Flexion (Bent Knee)", bundle: .module)
                #endif
            }(),
        ]
        if let override = overrides[id] { return override }
        return id.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
}
