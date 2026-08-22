import Foundation

// Field-testing §03 — a faceted exercise taxonomy (exrx-structured, original
// data). Equipment, mechanics, force, and a muscle catalog with scientific +
// colloquial synonyms power fast keyword search ("cable", "lats", "push").

/// How the user-entered weight maps to effective load for calculations.
/// Stored as a String on Exercise (default) and SetEntry (snapshot).
public enum LoadAccountingMode: String, CaseIterable, Codable, Sendable {
    case barbell            // entered = added plate load; effective = (entered + barWeight) * multiplier
    case bodyweight         // entered = added load only; effective = entered * multiplier
    case dualDumbbell       // entered = one dumbbell; effective = entered * 2
    case singleDumbbell     // entered = one dumbbell; effective = entered * 1
    case isolateralDumbbell // entered = one dumbbell; effective = entered * 2 (comparison mode)
    case dualKettlebell       // entered = one kettlebell; effective = entered * 2
    case singleKettlebell     // entered = one kettlebell; effective = entered * 1
    case isolateralKettlebell // entered = one kettlebell; effective = entered * 2 (comparison mode)
}

/// How the exercise is loaded (decision #11). Isolateral/unilateral is a
/// separate `isLateral` flag on the exercise so it composes with any equipment.
public enum Equipment: String, CaseIterable, Codable, Sendable, Identifiable {
    case barbell, dumbbell, cable, machine, bodyweight, plyometric, kettlebell, band, smith
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbell"
        case .cable: return "Cable"
        case .machine: return "Machine"
        case .bodyweight: return "Bodyweight"
        case .plyometric: return "Plyometric"
        case .kettlebell: return "Kettlebell"
        case .band: return "Band"
        case .smith: return "Smith Machine"
        }
    }
}

/// Joint involvement (exrx "mechanics").
public enum Mechanics: String, CaseIterable, Codable, Sendable {
    case compound, isolation
}

/// Resistance direction (exrx "force"), distinct from the training-split
/// `ExerciseCategory`.
public enum Force: String, CaseIterable, Codable, Sendable {
    case push, pull, `static`
}

/// Broad body region for grouping/search.
public enum BodyRegion: String, CaseIterable, Codable, Sendable {
    case chest, back, shoulders, arms, core, legs, glutes, fullBody
}

/// A muscle with its scientific name, colloquial synonyms, and region
/// (decision #12). Used both for tagging exercises and resolving search terms.
public struct Muscle: Equatable, Sendable, Identifiable {
    public let id: String          // canonical key, e.g. "lats"
    public let scientific: String  // "Latissimus Dorsi"
    public let synonyms: [String]  // ["lats","lat"]
    public let region: BodyRegion

    public init(id: String, scientific: String, synonyms: [String], region: BodyRegion) {
        self.id = id
        self.scientific = scientific
        self.synonyms = synonyms
        self.region = region
    }

    /// All searchable terms for this muscle, lowercased.
    public var searchTerms: [String] {
        ([id, scientific] + synonyms).map { $0.lowercased() }
    }
}

/// The canonical muscle catalog + synonym resolution.
public enum MuscleCatalog {
    public static let all: [Muscle] = [
        .init(id: "chest", scientific: "Pectoralis Major", synonyms: ["pecs", "pec", "chest"], region: .chest),
        .init(id: "upper-chest", scientific: "Clavicular Pectoralis", synonyms: ["upper chest", "upper pecs"], region: .chest),
        .init(id: "lats", scientific: "Latissimus Dorsi", synonyms: ["lats", "lat", "wings"], region: .back),
        .init(id: "traps", scientific: "Trapezius", synonyms: ["traps", "trap"], region: .back),
        .init(id: "rhomboids", scientific: "Rhomboids", synonyms: ["rhomboids", "mid back"], region: .back),
        .init(id: "lower-back", scientific: "Erector Spinae", synonyms: ["lower back", "spinal erectors", "erectors"], region: .back),
        .init(id: "delts", scientific: "Deltoid", synonyms: ["delts", "delt", "shoulders"], region: .shoulders),
        .init(id: "front-delts", scientific: "Anterior Deltoid", synonyms: ["front delts", "anterior delt"], region: .shoulders),
        .init(id: "rear-delts", scientific: "Posterior Deltoid", synonyms: ["rear delts", "posterior delt"], region: .shoulders),
        .init(id: "biceps", scientific: "Biceps Brachii", synonyms: ["bis", "bicep", "biceps"], region: .arms),
        .init(id: "triceps", scientific: "Triceps Brachii", synonyms: ["tris", "tricep", "triceps"], region: .arms),
        .init(id: "forearms", scientific: "Forearm Flexors", synonyms: ["forearms", "grip"], region: .arms),
        .init(id: "abs", scientific: "Rectus Abdominis", synonyms: ["abs", "core", "six pack"], region: .core),
        .init(id: "obliques", scientific: "Obliques", synonyms: ["obliques", "side abs"], region: .core),
        .init(id: "quads", scientific: "Quadriceps", synonyms: ["quads", "quad", "thighs"], region: .legs),
        .init(id: "hamstrings", scientific: "Hamstrings", synonyms: ["hams", "hamstring"], region: .legs),
        .init(id: "glutes", scientific: "Gluteus Maximus", synonyms: ["glutes", "glute", "butt"], region: .glutes),
        .init(id: "calves", scientific: "Gastrocnemius", synonyms: ["calves", "calf"], region: .legs),
        .init(id: "adductors", scientific: "Hip Adductors", synonyms: ["adductors", "inner thigh"], region: .legs),
        .init(id: "abductors", scientific: "Hip Abductors", synonyms: ["abductors", "outer thigh"], region: .legs),
        .init(id: "hip-flexors", scientific: "Hip Flexors", synonyms: ["hip flexors"], region: .legs),
    ]

    private static let byID: [String: Muscle] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Strict, deterministic descending mass order used only when equally-sized
    /// weekly deficits need a next muscle. This is an anatomical planning
    /// heuristic for the average adult, not a claim about any individual's body.
    public static let descendingMassOrder = [
        "glutes", "quads", "lats", "chest", "hamstrings", "traps", "delts",
        "calves", "lower-back", "adductors", "triceps", "abs", "biceps",
        "forearms", "obliques", "rhomboids", "abductors", "hip-flexors",
        "upper-chest", "front-delts", "rear-delts"
    ]

    private static let massPriorityByID = Dictionary(
        uniqueKeysWithValues: descendingMassOrder.enumerated().map { ($0.element, $0.offset) }
    )

    /// Lower values are larger muscles. Unknown IDs deliberately sort last.
    public static func massPriority(for id: String) -> Int {
        massPriorityByID[id] ?? Int.max
    }

    public static func muscle(_ id: String) -> Muscle? { byID[id] }

    /// All searchable terms for a muscle id (id + scientific + synonyms + region).
    public static func searchTerms(for id: String) -> [String] {
        guard let m = byID[id] else { return [id.lowercased()] }
        return m.searchTerms + [m.region.rawValue.lowercased()]
    }

    /// Canonicalize an exercise name for matching purposes. Strips equipment,
    /// grip, and laterality qualifiers so "Double Kettlebell Snatch" and
    /// "Snatch" resolve to the same matching key. Does NOT mutate stored
    /// exerciseName — this is a matching key only.
    public static func canonicalName(_ name: String) -> String {
        let lower = name.lowercased()

        let qualifiers: [String] = [
            "double kettlebell", "single kettlebell",
            "double dumbbell", "single dumbbell",
            "double", "single",
            "kettlebell", "dumbbell", "barbell",
            "standing", "seated",
            "alternate", "alternating",
            "machine", "cable",
            "smith",
            "- pronated grip", "- supinated grip",
            "pronated grip", "supinated grip",
            "banded",
        ]

        var result = lower
        for qualifier in qualifiers {
            result = result.replacingOccurrences(of: qualifier, with: "")
        }

        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.trimmingCharacters(in: .whitespaces)

        return result.isEmpty ? lower : result
    }
}
