import Foundation

/// The canonical training dimension: free-exercise-db++'s evidence-audited
/// 20-muscle ontology. Raw values are DB++'s strings verbatim, so an annotation
/// reads straight into this type with no translation table, and
/// `TrainingEngineDatabaseTests` fails if a data refresh ever moves the two apart.
///
/// This replaces BOTH the 8-case `BodyPart` and the 21-entry `MuscleCatalog`
/// (DB++ adoption, 2026-08-23, decision D2). The old fine catalog claimed a
/// resolution the data never had: `upper-chest`, `front-delts`, `rear-delts`,
/// `obliques` and `rhomboids` were reachable only from 19 hand-written entries out
/// of ~1000 seeded exercises, so they showed as permanent deficits nobody could
/// close. Every group here has real exercises behind it.
public enum MuscleGroup: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case abdominals
    case abductors
    case adductors
    case biceps
    case calves
    case chest
    case forearms
    case glutes
    case hamstrings
    case lats
    case lowerBack = "lower_back"
    case middleBack = "middle_back"
    case neck
    case quadriceps
    case shoulders
    case traps
    case triceps
    case tibialis
    case rotatorCuff = "rotator_cuff"
    case hipFlexors = "hip_flexors"

    public var id: String { rawValue }

    // MARK: Descriptors

    public var displayName: String {
        switch self {
        case .abdominals: "Abs"
        case .abductors: "Abductors"
        case .adductors: "Adductors"
        case .biceps: "Biceps"
        case .calves: "Calves"
        case .chest: "Chest"
        case .forearms: "Forearms"
        case .glutes: "Glutes"
        case .hamstrings: "Hamstrings"
        case .lats: "Lats"
        case .lowerBack: "Lower Back"
        case .middleBack: "Mid Back"
        case .neck: "Neck"
        case .quadriceps: "Quads"
        case .shoulders: "Shoulders"
        case .traps: "Traps"
        case .triceps: "Triceps"
        case .tibialis: "Tibialis"
        case .rotatorCuff: "Rotator Cuff"
        case .hipFlexors: "Hip Flexors"
        }
    }

    public var scientificName: String {
        switch self {
        case .abdominals: "Rectus Abdominis"
        case .abductors: "Hip Abductors"
        case .adductors: "Hip Adductors"
        case .biceps: "Biceps Brachii"
        case .calves: "Triceps Surae"
        case .chest: "Pectoralis Major"
        case .forearms: "Forearm Flexors and Extensors"
        case .glutes: "Gluteus Maximus"
        case .hamstrings: "Hamstrings"
        case .lats: "Latissimus Dorsi"
        case .lowerBack: "Erector Spinae"
        case .middleBack: "Rhomboids and Middle Trapezius"
        case .neck: "Cervical Flexors and Extensors"
        case .quadriceps: "Quadriceps"
        case .shoulders: "Deltoid"
        case .traps: "Trapezius"
        case .triceps: "Triceps Brachii"
        case .tibialis: "Tibialis Anterior"
        case .rotatorCuff: "Rotator Cuff"
        case .hipFlexors: "Iliopsoas"
        }
    }

    /// Colloquial search terms. These deliberately absorb the retired fine-grained
    /// names (`obliques`, `upper chest`, `front delts`, `rear delts`, `rhomboids`)
    /// so a user searching for them still finds the right movements.
    public var synonyms: [String] {
        switch self {
        case .abdominals: ["abs", "core", "six pack", "obliques", "stomach"]
        case .abductors: ["abductors", "outer thigh", "glute medius"]
        case .adductors: ["adductors", "inner thigh", "groin"]
        case .biceps: ["bis", "bicep", "biceps"]
        case .calves: ["calves", "calf", "gastroc", "soleus"]
        case .chest: ["pecs", "pec", "chest", "upper chest"]
        case .forearms: ["forearms", "grip", "wrists"]
        case .glutes: ["glutes", "glute", "butt", "hips"]
        case .hamstrings: ["hams", "hamstring", "posterior chain"]
        case .lats: ["lats", "lat", "wings"]
        case .lowerBack: ["lower back", "erectors", "spinal erectors"]
        case .middleBack: ["mid back", "middle back", "rhomboids", "upper back"]
        case .neck: ["neck"]
        case .quadriceps: ["quads", "quad", "thighs"]
        case .shoulders: ["delts", "delt", "shoulders", "front delts", "rear delts", "side delts"]
        case .traps: ["traps", "trap"]
        case .triceps: ["tris", "tricep", "triceps"]
        case .tibialis: ["tibialis", "shins", "shin"]
        case .rotatorCuff: ["rotator cuff", "cuff", "external rotators"]
        case .hipFlexors: ["hip flexors", "psoas", "iliopsoas"]
        }
    }

    /// Broad body region. A grouping and ordering aid for pickers and section
    /// headers ONLY — never a volume dimension. Collapsing volume onto regions is
    /// exactly the simplification this type exists to remove.
    public var region: BodyRegion {
        switch self {
        case .chest: .chest
        case .lats, .middleBack, .lowerBack, .traps, .neck: .back
        case .shoulders, .rotatorCuff: .shoulders
        case .biceps, .triceps, .forearms: .arms
        case .abdominals: .core
        case .glutes: .glutes
        case .quadriceps, .hamstrings, .calves, .adductors, .abductors, .hipFlexors, .tibialis: .legs
        }
    }

    /// All lowercased search tokens for this group.
    public var searchTerms: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for term in [rawValue.replacingOccurrences(of: "_", with: " "), displayName,
                     scientificName, region.rawValue] + synonyms {
            let normalized = term.lowercased()
            if seen.insert(normalized).inserted { out.append(normalized) }
        }
        return out
    }

    // MARK: Ordering

    /// Strict descending average-muscle-mass order, used only to break equal weekly
    /// deficits deterministically. An anatomical planning heuristic for the average
    /// adult, not a claim about any individual's body.
    public static let descendingMassOrder: [MuscleGroup] = [
        .glutes, .quadriceps, .lats, .chest, .hamstrings, .traps, .shoulders,
        .middleBack, .lowerBack, .calves, .adductors, .triceps, .abdominals,
        .biceps, .forearms, .abductors, .hipFlexors, .neck, .rotatorCuff, .tibialis
    ]

    private static let massPriorityByGroup: [MuscleGroup: Int] = Dictionary(
        uniqueKeysWithValues: descendingMassOrder.enumerated().map { ($0.element, $0.offset) }
    )

    /// Lower values are larger muscles. An unknown group deliberately sorts last.
    public static func massPriority(for group: MuscleGroup) -> Int {
        massPriorityByGroup[group] ?? Int.max
    }

    // MARK: Coverage

    /// The groups the coach programs toward and Home always shows a row for
    /// (decision D4). The rest are shown only once the user has actually trained
    /// them, and are never targeted.
    ///
    /// The excluded groups are intentionally not coach targets: they have limited
    /// or specialised coverage, or are normally trained as stabilisers and
    /// indirect work in compound lifts. Users who want to program them can do so
    /// via `CoachSchedulePreferences.trackedMuscleGroups`.
    public static let defaultTracked: Set<MuscleGroup> = [
        .abdominals, .biceps, .calves, .chest, .forearms, .glutes, .hamstrings,
        .lats, .middleBack, .quadriceps, .shoulders, .traps, .triceps
    ]

    public var isTrackedByDefault: Bool { Self.defaultTracked.contains(self) }

    /// Deterministic display order: tracked groups first in `descendingMassOrder`,
    /// then the rest in the same order. Callers that want an alphabetical list sort
    /// `displayName` themselves.
    public static let canonicalOrder: [MuscleGroup] =
        descendingMassOrder.filter { defaultTracked.contains($0) }
        + descendingMassOrder.filter { !defaultTracked.contains($0) }

    private static let canonicalIndexByGroup: [MuscleGroup: Int] = Dictionary(
        uniqueKeysWithValues: canonicalOrder.enumerated().map { ($0.element, $0.offset) }
    )

    /// Position in `canonicalOrder` — the tie-break every list, deficit sort and
    /// diagnostic ordering uses, so two surfaces can never disagree about order.
    public static func canonicalIndex(_ group: MuscleGroup) -> Int {
        canonicalIndexByGroup[group] ?? Int.max
    }

    /// Groups sorted into `canonicalOrder`.
    public static func sorted(_ groups: some Sequence<MuscleGroup>) -> [MuscleGroup] {
        groups.sorted { canonicalIndex($0) < canonicalIndex($1) }
    }

    /// The lower body, for the optimizer's upper/lower split classification.
    /// `abdominals` is deliberately absent: core work is treated as neutral.
    public static let lowerBody: Set<MuscleGroup> = [
        .quadriceps, .hamstrings, .glutes, .calves, .adductors, .abductors,
        .hipFlexors, .tibialis
    ]

    // MARK: Canonicalization

    /// Every string that resolves to a group: DB++ raw values, the retired
    /// `MuscleCatalog` ids, and upstream free-exercise-db spellings.
    private static let aliases: [String: MuscleGroup] = {
        var table: [String: MuscleGroup] = [:]
        for group in allCases { table[group.rawValue] = group }
        // Retired MuscleCatalog ids. The fine-grained ones fold into the group the
        // evidence can actually distinguish (decision D7).
        table["abs"] = .abdominals
        table["obliques"] = .abdominals
        table["quads"] = .quadriceps
        table["delts"] = .shoulders
        table["front_delts"] = .shoulders
        table["rear_delts"] = .shoulders
        table["side_delts"] = .shoulders
        table["rhomboids"] = .middleBack
        table["upper_chest"] = .chest
        // Upstream spellings normalise into raw values via the underscore
        // substitution in `canonical(_:)`, so "lower back" and "middle back" are
        // already covered. `neck` maps to itself: the pre-DB++ import mapped it onto
        // traps, which this replaces.
        return table
    }()

    /// Resolves any historical, upstream, or user-typed muscle string to a group.
    /// Returns `nil` for genuinely unknown input rather than guessing.
    public static func canonical(_ value: String) -> MuscleGroup? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        guard !normalized.isEmpty else { return nil }
        return aliases[normalized]
    }

    /// Canonicalizes a list, preserving order and dropping duplicates and unknowns.
    public static func canonicalize(_ values: [String]) -> [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        var out: [MuscleGroup] = []
        for value in values {
            if let group = canonical(value), seen.insert(group).inserted { out.append(group) }
        }
        return out
    }

    /// Default groups for an exercise category, used when creating a custom
    /// exercise with no template to copy facets from.
    public static func defaults(forCategory category: ExerciseCategory) -> [MuscleGroup] {
        switch category {
        case .push: [.chest, .shoulders, .triceps]
        case .pull: [.lats, .biceps]
        case .legs: [.quadriceps, .hamstrings, .glutes]
        case .core: [.abdominals]
        case .cardio, .plyometrics, .other: []
        }
    }
}
