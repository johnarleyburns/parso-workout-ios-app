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
    public let id: Int            // stable order
    public let movement: String   // must match an `ExerciseLibrary` name
    public let reps: Int?         // prescribed reps per round/pass
    public let distanceM: Double? // 400 m run, 1000 m row
    public let loadLb: Double?    // canonical Rx load (male), pounds
    public let loadLbFemale: Double?
    public let targetSets: Int?   // strength presets / custom
    public let note: String?      // "1.5/1 pood", "20/14 ball"

    public init(id: Int, movement: String, reps: Int? = nil, distanceM: Double? = nil,
                loadLb: Double? = nil, loadLbFemale: Double? = nil,
                targetSets: Int? = nil, note: String? = nil) {
        self.id = id
        self.movement = movement
        self.reps = reps
        self.distanceM = distanceM
        self.loadLb = loadLb
        self.loadLbFemale = loadLbFemale
        self.targetSets = targetSets
        self.note = note
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
