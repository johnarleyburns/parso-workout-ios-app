import Foundation

// Round 4 Part B — a concrete "prescribed work" model (round4b-plan.md §core).
// Pure value types: the built-in strength-preset catalog lives in code as the
// single source of truth. A launched `WorkoutSession` remembers its plan via an
// additive `planKey` and resolves it here, so there is no SwiftData schema for
// plans and nothing to migrate.

/// Where a plan came from (decision: builtin catalog only for v1; `.user` is
/// reserved for the future custom-plan store).
public enum PlanSource: String, Codable, Sendable {
    case strengthPreset, user
}

/// The prescribed scheme — how the work is structured + timed. Strength is the
/// only scheme (presets + custom builder, B-2): items carry target sets/reps.
public enum WorkoutScheme: Equatable, Sendable, Codable {
    case strength
}

/// One prescribed movement within a plan.
public struct PlanItem: Equatable, Sendable, Codable, Identifiable {
    public let id: Int
    public let movement: String
    public let reps: Int?
    public let distanceM: Double?
    public let loadLb: Double?
    public let loadLbFemale: Double?
    public let targetSets: Int?
    public let note: String?
    public let loadPercentage: Double?

    public init(id: Int, movement: String, reps: Int? = nil, distanceM: Double? = nil,
                loadLb: Double? = nil, loadLbFemale: Double? = nil,
                targetSets: Int? = nil, note: String? = nil,
                loadPercentage: Double? = nil) {
        self.id = id
        self.movement = movement
        self.reps = reps
        self.distanceM = distanceM
        self.loadLb = loadLb
        self.loadLbFemale = loadLbFemale
        self.targetSets = targetSets
        self.note = note
        self.loadPercentage = loadPercentage
    }
}

/// A concrete, prescribed workout (a strength preset or a user's custom build).
public struct WorkoutPlan: Equatable, Sendable, Identifiable {
    public let id: String         // stable key: "fran", "preset-5x5"
    public let name: String
    public let source: PlanSource
    public let scheme: WorkoutScheme
    public let items: [PlanItem]
    public let notes: String?
    /// A "template" strength preset (Push/Pull/Legs, calisthenics …) whose
    /// set/rep scheme is chosen at launch via the rep-scheme chooser and applied
    /// to every movement (feedback batch 3). Fixed programs (5×5, Olympic days)
    /// carry their own scheme and leave this false.
    public let flexibleScheme: Bool

    public init(id: String, name: String, source: PlanSource,
                scheme: WorkoutScheme, items: [PlanItem], notes: String? = nil,
                flexibleScheme: Bool = false) {
        self.id = id
        self.name = name
        self.source = source
        self.scheme = scheme
        self.items = items
        self.notes = notes
        self.flexibleScheme = flexibleScheme
    }

    /// Movement names to pre-load into the session (first appearance order,
    /// de-duplicated so a movement used twice isn't double-listed).
    public var movementNames: [String] {
        var seen = Set<String>()
        return items.compactMap { seen.insert($0.movement).inserted ? $0.movement : nil }
    }

    /// Title to stamp on a launched session — strength presets keep their plain
    /// name ("5×5", "Push").
    public var displayTitle: String { name }

    /// A short, human display of the scheme. Strength is the only scheme.
    public var schemeSummary: String {
        switch scheme {
        case .strength: return "Strength"
        }
    }
}

// MARK: - Strength preset library (round4b feedback #1)

/// Built-in "Start from Library" strength workouts — the common splits a lifter
/// reaches for (5×5, Push/Pull/Legs, Upper/Lower, body-part days, Olympic). Each
/// is a `.strength` plan whose items carry target sets×reps; launching one
/// pre-loads the movements as ghost cards with a prescription line, ready to log.
/// Movement names match `ExerciseLibrary` so they resolve to real catalog rows.
public enum StrengthPresets {
    /// A fixed program: each movement carries its own target sets×reps and
    /// launches straight to the preview (no rep-scheme chooser).
    private static func fixed(_ id: String, _ name: String,
                             _ movements: [(String, Int, Int)]) -> WorkoutPlan {
        WorkoutPlan(id: id, name: name, source: .strengthPreset, scheme: .strength,
                    items: movements.enumerated().map { i, m in
                        PlanItem(id: i, movement: m.0, reps: m.2, targetSets: m.1)
                    })
    }

    private static func fixedPct(_ id: String, _ name: String,
                                 mainLift: (String, Int, Int, Double),
                                 accessories: [(String, Int, Int)]) -> WorkoutPlan {
        var items: [PlanItem] = [
            PlanItem(id: 0, movement: mainLift.0, reps: mainLift.2,
                     targetSets: mainLift.1, loadPercentage: mainLift.3)
        ]
        for (i, m) in accessories.enumerated() {
            items.append(PlanItem(id: i + 1, movement: m.0, reps: m.2, targetSets: m.1))
        }
        return WorkoutPlan(id: id, name: name, source: .strengthPreset, scheme: .strength, items: items)
    }

    private static func fixedPct2(_ id: String, _ name: String,
                                  t1: (String, Int, Int, Double),
                                  t2: (String, Int, Int, Double),
                                  accessories: [(String, Int, Int)]) -> WorkoutPlan {
        var items: [PlanItem] = [
            PlanItem(id: 0, movement: t1.0, reps: t1.2,
                     targetSets: t1.1, loadPercentage: t1.3),
            PlanItem(id: 1, movement: t2.0, reps: t2.2,
                     targetSets: t2.1, loadPercentage: t2.3),
        ]
        for (i, m) in accessories.enumerated() {
            items.append(PlanItem(id: i + 2, movement: m.0, reps: m.2, targetSets: m.1))
        }
        return WorkoutPlan(id: id, name: name, source: .strengthPreset, scheme: .strength, items: items)
    }

    /// A flexible template: just a movement list. The set/rep scheme is chosen at
    /// launch and applied to every movement (the listed `defaultReps` is only a
    /// sensible fallback for the preview).
    private static func template(_ id: String, _ name: String,
                                 _ movements: [String], defaultReps: Int = 10) -> WorkoutPlan {
        WorkoutPlan(id: id, name: name, source: .strengthPreset, scheme: .strength,
                    items: movements.enumerated().map { i, m in
                        PlanItem(id: i, movement: m, reps: defaultReps, targetSets: 3)
                    },
                    flexibleScheme: true)
    }

    // StrongLifts-style 5×5: A = Squat/Bench/Row, B = Squat/Press/Deadlift.
    // Weeks 1/2 are progression labels (load climbs week to week).
    private static let fiveByFiveA: [(String, Int, Int)] = [
        ("Back Squat", 5, 5), ("Bench Press", 5, 5), ("Barbell Row", 5, 5),
    ]
    private static let fiveByFiveB: [(String, Int, Int)] = [
        ("Back Squat", 5, 5), ("Overhead Press", 5, 5), ("Deadlift", 1, 5),
    ]

    public static let all: [WorkoutPlan] = [
        // 5×5 — four alternating days across two weeks (feedback batch 3).
        fixed("preset-5x5-1a", "5×5 Week 1A", fiveByFiveA),
        fixed("preset-5x5-1b", "5×5 Week 1B", fiveByFiveB),
        fixed("preset-5x5-2a", "5×5 Week 2A", fiveByFiveA),
        fixed("preset-5x5-2b", "5×5 Week 2B", fiveByFiveB),
        // Flexible split templates — pick a set/rep scheme at launch.
        template("preset-push", "Push", [
            "Bench Press", "Overhead Press", "Incline Dumbbell Bench Press",
            "Triceps Pushdown", "Dumbbell Lateral Raise",
        ]),
        template("preset-pull", "Pull", [
            "Deadlift", "Pull-Up", "Seated Cable Row", "Face Pull", "Barbell Curl",
        ]),
        template("preset-legs", "Legs", [
            "Back Squat", "Romanian Deadlift", "Leg Press", "Lying Leg Curl",
            "Standing Calf Raise",
        ]),
        template("preset-upper", "Upper", [
            "Bench Press", "Barbell Row", "Overhead Press", "Lat Pulldown",
            "Barbell Curl", "Triceps Pushdown",
        ]),
        template("preset-lower", "Lower", [
            "Back Squat", "Romanian Deadlift", "Leg Press", "Leg Extension",
            "Standing Calf Raise",
        ]),
        template("preset-chest", "Chest", [
            "Bench Press", "Incline Dumbbell Bench Press", "Cable Fly", "Dip",
        ]),
        template("preset-back-bi", "Back & Biceps", [
            "Deadlift", "Pull-Up", "Seated Cable Row", "Barbell Curl", "Hammer Curl",
        ]),
        // Bodyweight / calisthenics templates (feedback batch 3).
        template("preset-cali-push", "Calisthenics Push", [
            "Push-Up", "Dip", "Pike Push-Up", "Decline Push-Up",
        ]),
        template("preset-cali-pull", "Calisthenics Pull", [
            "Pull-Up", "Chin-Up", "Inverted Row", "Hanging Leg Raise",
        ]),
        template("preset-cali-legs", "Calisthenics Legs & Core", [
            "Air Squat", "Bulgarian Split Squat", "Glute Bridge", "Plank",
        ]),
        // Olympic — three focused days (feedback batch 3).
        fixed("preset-oly-snatch", "Olympic Snatch Day", [("Snatch", 20, 1)]),
        fixed("preset-oly-cj", "Olympic Clean & Jerk Day", [("Clean and Jerk", 20, 1)]),
        fixed("preset-oly-mixed", "Olympic Mixed Day", [
            ("Snatch", 5, 3), ("Clean and Jerk", 5, 2), ("Front Squat", 4, 5),
            ("Overhead Squat", 3, 5), ("Power Clean", 4, 3),
        ]),
        // 5/3/1 (Wendler) — four main-lift days. Each day: the main lift at
        // 5/3/1 progression with percentage-based loading, then accessories.
        // Based on Jim Wendler's 5/3/1 methodology. Percentages are of tested 1RM.
        fixedPct("preset-531-squat", "5/3/1 Squat Day",
                 mainLift: ("Back Squat", 3, 5, 0.75),
                 accessories: [("Leg Press", 3, 10), ("Seated Leg Curl", 3, 10), ("Ab Roller", 3, 15)]),
        fixedPct("preset-531-bench", "5/3/1 Bench Day",
                 mainLift: ("Bench Press", 3, 5, 0.75),
                 accessories: [("One-Arm Dumbbell Row", 3, 10), ("Dip", 3, 10), ("Face Pull", 3, 15)]),
        fixedPct("preset-531-deadlift", "5/3/1 Deadlift Day",
                 mainLift: ("Deadlift", 3, 5, 0.75),
                 accessories: [("Hanging Leg Raise", 3, 15), ("Good Morning", 3, 10), ("Dumbbell Shrug", 3, 12)]),
        fixedPct("preset-531-press", "5/3/1 Press Day",
                 mainLift: ("Overhead Press", 3, 5, 0.75),
                 accessories: [("Chin-Up", 3, 8), ("Dumbbell Lateral Raise", 3, 12), ("Barbell Curl", 3, 10)]),
        // GZCLP — four sessions: T1 (heavy compound, 5x3), T2 (moderate
        // compound, 3x10), T3 (light isolation, 3x15). Based on Cody Lefever's
        // General Gainz / GZCLP linear progression.
        fixed("preset-gzclp-a1", "GZCLP A1", [
            ("Back Squat", 5, 3), ("Bench Press", 3, 10), ("Lat Pulldown", 3, 15),
        ]),
        fixed("preset-gzclp-b1", "GZCLP B1", [
            ("Overhead Press", 5, 3), ("Deadlift", 3, 10), ("Barbell Row", 3, 15),
        ]),
        fixed("preset-gzclp-a2", "GZCLP A2", [
            ("Bench Press", 5, 3), ("Back Squat", 3, 10), ("Lat Pulldown", 3, 15),
        ]),
        fixed("preset-gzclp-b2", "GZCLP B2", [
            ("Deadlift", 5, 3), ("Overhead Press", 3, 10), ("Barbell Row", 3, 15),
        ]),
        // nSuns 5/3/1 LP — high-volume 5/3/1 variant with 8-9 working sets
        // per main lift at prescribed percentages. Based on the nSuns community
        // linear progression variant of 5/3/1. Percentages are of tested 1RM.
        fixedPct2("preset-nsuns-bench", "nSuns Bench + OHP",
                  t1: ("Bench Press", 9, 3, 0.80),
                  t2: ("Overhead Press", 8, 3, 0.65),
                  accessories: [("Cable Fly", 3, 12), ("Triceps Pushdown", 3, 12), ("Face Pull", 3, 15)]),
        fixedPct2("preset-nsuns-squat", "nSuns Squat + Sumo DL",
                  t1: ("Back Squat", 9, 3, 0.80),
                  t2: ("Sumo Deadlift", 8, 3, 0.65),
                  accessories: [("Leg Press", 3, 10), ("Seated Leg Curl", 3, 12), ("Ab Roller", 3, 15)]),
        fixedPct2("preset-nsuns-ohp", "nSuns OHP + Incline",
                  t1: ("Overhead Press", 9, 3, 0.80),
                  t2: ("Incline Dumbbell Bench Press", 8, 3, 0.65),
                  accessories: [("Dumbbell Lateral Raise", 3, 12), ("Barbell Curl", 3, 10), ("Face Pull", 3, 15)]),
        fixedPct2("preset-nsuns-deadlift", "nSuns Deadlift + Front Squat",
                  t1: ("Deadlift", 9, 3, 0.80),
                  t2: ("Front Squat", 8, 3, 0.65),
                  accessories: [("Barbell Row", 3, 10), ("Hanging Leg Raise", 3, 15), ("Hammer Curl", 3, 12)]),
        // PPL 6-day — Push/Pull/Legs with A/B variations. A common beginner-to-
        // intermediate program popularized on r/Fitness. Two rotations per week.
        template("preset-ppl-push-a", "PPL Push A", [
            "Bench Press", "Overhead Press", "Incline Dumbbell Bench Press",
            "Triceps Pushdown", "Dumbbell Lateral Raise", "Standing Dumbbell Triceps Extension",
        ]),
        template("preset-ppl-pull-a", "PPL Pull A", [
            "Deadlift", "Pull-Up", "Seated Cable Row",
            "Face Pull", "Barbell Curl", "Hammer Curl",
        ]),
        template("preset-ppl-legs-a", "PPL Legs A", [
            "Back Squat", "Romanian Deadlift", "Leg Press",
            "Seated Leg Curl", "Standing Calf Raise",
        ]),
        template("preset-ppl-push-b", "PPL Push B", [
            "Overhead Press", "Bench Press", "Dumbbell Bench Press",
            "Dumbbell Lateral Raise", "Triceps Pushdown", "Cable Fly",
        ]),
        template("preset-ppl-pull-b", "PPL Pull B", [
            "Barbell Row", "Pull-Up", "Lat Pulldown",
            "Face Pull", "Barbell Curl", "Standing Dumbbell Reverse Curl",
        ]),
        template("preset-ppl-legs-b", "PPL Legs B", [
            "Front Squat", "Romanian Deadlift", "Leg Extension",
            "Seated Leg Curl", "Standing Calf Raise",
        ]),
    ]
}

// MARK: - Plan resolution

/// Resolves a `WorkoutSession.planKey` back to its plan in the built-in strength
/// preset catalog. Returns nil for ad-hoc sessions and legacy keys (e.g. a
/// removed CrossFit benchmark), which then render read-only from their stored title.
public enum PlanCatalog {
    public static func plan(forKey key: String) -> WorkoutPlan? {
        StrengthPresets.all.first { $0.id == key }
    }
}
