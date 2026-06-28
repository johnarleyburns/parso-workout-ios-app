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
public enum WorkoutScheme: Equatable, Hashable, Sendable, Codable {
    case strength
}

/// One prescribed movement within a plan.
public struct PlanItem: Equatable, Hashable, Sendable, Codable, Identifiable {
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
public struct WorkoutPlan: Equatable, Hashable, Sendable, Identifiable {
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

    /// A guaranteed non-empty fallback used when `all` is somehow empty, so
    /// `pickRoutine` never has to force-index an empty array. Independent of `all`.
    public static let fallback: WorkoutPlan = template("preset-fullbody-fallback", "Full Body", [
        "Back Squat", "Bench Press", "Deadlift",
    ])

    public static let all: [WorkoutPlan] = [
        // 5×5 — four alternating days across two weeks (feedback batch 3).
        // Science: Krieger 2010 multi-set meta-analysis.
        fixed("preset-5x5-1a", "5\u{00d7}5 Week 1A", fiveByFiveA),
        fixed("preset-5x5-1b", "5\u{00d7}5 Week 1B", fiveByFiveB),
        fixed("preset-5x5-2a", "5\u{00d7}5 Week 2A", fiveByFiveA),
        fixed("preset-5x5-2b", "5\u{00d7}5 Week 2B", fiveByFiveB),
        // Flexible split templates — pick a set/rep scheme at launch.
        // Science: Schoenfeld 2019 frequency meta-analysis.
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
        // Science: Calatayud 2015 — bodyweight produces comparable activation.
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
        // Science: Channell & Barfield 2008 — Oly lifts for power.
        fixed("preset-oly-snatch", "Olympic Snatch Day", [("Snatch", 20, 1)]),
        fixed("preset-oly-cj", "Olympic Clean & Jerk Day", [("Clean and Jerk", 20, 1)]),
        fixed("preset-oly-mixed", "Olympic Mixed Day", [
            ("Snatch", 5, 3), ("Clean and Jerk", 5, 2), ("Front Squat", 4, 5),
            ("Overhead Squat", 3, 5), ("Power Clean", 4, 3),
        ]),
        // 5/3/1 (Wendler) — four main-lift days. Percentage-based loading.
        // Science: Rhea & Alderman 2004 — periodization meta-analysis.
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
        // DUP (Daily Undulating Periodization) — three days rotating intensity.
        // Science: Zourdos 2016 — modified DUP > traditional periodization.
        fixed("preset-dup-heavy", "DUP Heavy Day", [
            ("Back Squat", 5, 3), ("Bench Press", 5, 3), ("Barbell Row", 5, 3),
        ]),
        fixed("preset-dup-hypertrophy", "DUP Hypertrophy Day", [
            ("Front Squat", 4, 10), ("Incline Dumbbell Bench Press", 4, 10),
            ("Lat Pulldown", 4, 10), ("Dumbbell Lateral Raise", 3, 12),
        ]),
        fixed("preset-dup-power", "DUP Power Day", [
            ("Deadlift", 6, 2), ("Overhead Press", 6, 2), ("Pull-Up", 6, 3),
        ]),
        // GVT (10×10) removed from automatic Coach selection as of recovery-aware
        // redesign — the cited study (Amirthalingam 2017) found no advantage to 10
        // sets over 5. It remains available as an advanced user-chosen template only.

        // Linear Periodization — four-week mesocycle, decreasing reps.
        // Science: Williams 2017 — periodized > non-periodized for strength.
        fixed("preset-lp-w1", "LP Week 1 (Volume)", [
            ("Back Squat", 4, 12), ("Bench Press", 4, 12), ("Barbell Row", 4, 12),
        ]),
        fixed("preset-lp-w2", "LP Week 2 (Moderate)", [
            ("Back Squat", 4, 10), ("Bench Press", 4, 10), ("Barbell Row", 4, 10),
        ]),
        fixed("preset-lp-w3", "LP Week 3 (Strength)", [
            ("Back Squat", 4, 8), ("Bench Press", 4, 8), ("Barbell Row", 4, 8),
        ]),
        fixed("preset-lp-w4", "LP Week 4 (Peak)", [
            ("Back Squat", 5, 5), ("Bench Press", 5, 5), ("Barbell Row", 5, 5),
        ]),
        // Cluster Set Training — short intra-set rest preserves velocity.
        // Science: Tufano 2017 — cluster sets maintain power output.
        WorkoutPlan(id: "preset-cluster", name: "Cluster Sets", source: .strengthPreset,
                    scheme: .strength,
                    items: [
                        PlanItem(id: 0, movement: "Back Squat", reps: 3, targetSets: 5,
                                 note: "20s rest between singles within each cluster"),
                        PlanItem(id: 1, movement: "Bench Press", reps: 3, targetSets: 5,
                                 note: "20s rest between singles within each cluster"),
                        PlanItem(id: 2, movement: "Deadlift", reps: 3, targetSets: 5,
                                 note: "20s rest between singles within each cluster"),
                    ],
                    notes: "Cluster protocol: perform each rep, rest 20s, repeat for target reps per set. Full rest between sets."),
        // PPL 6-day — Push/Pull/Legs with A/B variations.
        // Science: Schoenfeld 2019 — \u{2265}2\u{00d7}/week frequency meta-analysis.
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

// MARK: - Routine info (science audit 2026-06-19)

public struct RoutineInfo: Sendable, Identifiable {
    public var id: String { groupName }
    public let groupName: String
    public let summary: String
    public let citations: [Citation]
}

public enum RoutineInfoCatalog {
    public static let fiveByFive = RoutineInfo(
        groupName: "5\u{00d7}5 Program",
        summary: "The 5\u{00d7}5 protocol prescribes five sets of five repetitions on compound barbell lifts, adding weight each session. It is one of the oldest and most replicated progressive-overload models in strength training, originating from Reg Park in the 1960s and formalized by Bill Starr.\n\nA meta-analysis by Krieger (2010) found that multiple-set protocols produce approximately 40% greater hypertrophy gains than single-set protocols, supporting the 5\u{00d7}5 volume as an effective dose for both strength and muscle growth in novice-to-intermediate trainees.",
        citations: [CitationRegistry.krieger2010]
    )

    public static let fiveThreeOne = RoutineInfo(
        groupName: "5/3/1",
        summary: "Wendler\u{2019}s 5/3/1 uses a four-week wave: sets of 5, then 3, then a heavy single followed by a rep-out set, with the fourth week as a deload. Each main lift progresses independently at prescribed percentages of a training max.\n\nRhea & Alderman\u{2019}s (2004) meta-analysis of 18 studies found that periodized programs \u{2014} which systematically vary intensity and volume over time, as 5/3/1 does \u{2014} produce significantly greater strength gains than non-periodized, fixed-scheme training.",
        citations: [CitationRegistry.rheaPeriodization]
    )

    public static let splits = RoutineInfo(
        groupName: "Split Templates",
        summary: "Body-part split templates (Push/Pull/Legs, Upper/Lower, Chest, Back & Biceps) distribute weekly training volume across focused sessions. This lets each muscle group recover while others are trained, supporting higher per-session volume.\n\nSchoenfeld, Grgic & Krieger\u{2019}s (2019) meta-analysis found that training each muscle group at least twice per week produces significantly greater hypertrophy than once-per-week splits, supporting multi-day split designs that hit each muscle \u{2265}2\u{00d7}/week.",
        citations: [CitationRegistry.frequencyMeta]
    )

    public static let ppl = RoutineInfo(
        groupName: "PPL (6-Day)",
        summary: "The Push/Pull/Legs 6-day split trains each movement pattern twice per week (Push A, Pull A, Legs A, Push B, Pull B, Legs B). The A/B variation provides exercise variety while maintaining the frequency stimulus.\n\nSchoenfeld, Grgic & Krieger\u{2019}s (2019) systematic review and meta-analysis demonstrated that training muscles at least twice per week leads to significantly greater hypertrophic outcomes compared to once per week, directly supporting the PPL frequency model.",
        citations: [CitationRegistry.frequencyMeta]
    )

    public static let calisthenics = RoutineInfo(
        groupName: "Calisthenics",
        summary: "Calisthenics programs use bodyweight exercises \u{2014} push-ups, pull-ups, dips, squats \u{2014} as the primary resistance. Progression comes from harder variations (decline push-ups, archer pull-ups, pistol squats) rather than external load.\n\nCalatayud et al. (2015) showed that when push-ups are performed at comparable levels of muscle activation to the bench press, both exercises produce similar strength gains. This supports bodyweight training as a viable alternative to loaded barbell work for upper-body strength development.",
        citations: [CitationRegistry.calatayudBodyweight]
    )

    public static let olympic = RoutineInfo(
        groupName: "Olympic Lifting",
        summary: "Olympic weightlifting \u{2014} the snatch and the clean & jerk \u{2014} develops explosive power, coordination, and full-body strength. These movements require high rates of force development and recruit large muscle groups through a full range of motion.\n\nChannell & Barfield (2008) compared Olympic-style and traditional resistance training in high school athletes and found that the Olympic group produced significantly greater improvements in vertical jump, a validated proxy for lower-body power output.",
        citations: [CitationRegistry.channellOlympic]
    )

    public static let dup = RoutineInfo(
        groupName: "DUP",
        summary: "Daily Undulating Periodization rotates intensity and volume within each training week \u{2014} heavy (low rep), hypertrophy (moderate rep), and power (explosive) days \u{2014} rather than changing across multi-week blocks.\n\nZourdos et al. (2016) found that a modified DUP model produced greater improvements in squat and bench press 1RM than a traditional periodization configuration in trained powerlifters, likely because frequent variation in training stimulus prevents accommodation.",
        citations: [CitationRegistry.zourdosDUP]
    )

    /// GVT removed from auto-selection: the cited study found no advantage to 10
    /// sets over 5. Kept as an advanced user-chosen template with this caveat.
    public static let gvt = RoutineInfo(
        groupName: "German Volume Training",
        summary: "German Volume Training (GVT) prescribes 10 sets of 10 repetitions on a compound lift at approximately 60% of 1RM, with 60\u{2013}90 seconds rest between sets. The extreme volume drives a strong hypertrophic stimulus.\n\nAmirthalingam et al. (2017) studied GVT in resistance-trained men and found significant increases in muscle thickness and lean body mass. The study also noted that a modified 5\u{00d7}10 protocol produced comparable results, suggesting the volume threshold for hypertrophy may be lower than GVT\u{2019}s traditional 10\u{00d7}10.",
        citations: [CitationRegistry.amirthalingamGVT]
    )

    public static let linearPeriodization = RoutineInfo(
        groupName: "Linear Periodization",
        summary: "Linear periodization progressively increases intensity while decreasing volume over a mesocycle \u{2014} for example, 4\u{00d7}12 in week one, 4\u{00d7}10, then 4\u{00d7}8, finishing with 5\u{00d7}5 at peak intensity. This systematic progression is the most widely studied model in resistance training.\n\nWilliams et al.\u{2019}s (2017) meta-analysis concluded that periodized resistance training programs produce significantly greater maximal-strength gains than non-periodized programs of matched volume and intensity, reinforcing the value of structured progression.",
        citations: [CitationRegistry.williamsLinearPeriodization]
    )

    public static let clusterSets = RoutineInfo(
        groupName: "Cluster Set Training",
        summary: "Cluster set training inserts short intra-set rest intervals (15\u{2013}30 seconds) between individual repetitions or small groups of reps within a set. This maintains bar velocity and power output across the set, reducing the fatigue-driven decline in performance.\n\nTufano, Brown & Haff\u{2019}s (2017) systematic review found that cluster set structures allow lifters to maintain higher movement velocity and power output compared to traditional sets, making them particularly effective for strength and power development.",
        citations: [CitationRegistry.tufanoCluster]
    )

    public static let all: [RoutineInfo] = [
        fiveByFive, fiveThreeOne, splits, ppl, calisthenics, olympic,
        dup, linearPeriodization, clusterSets,
    ]

    public static func info(forGroup group: String) -> RoutineInfo? {
        all.first { $0.groupName == group }
    }
}
