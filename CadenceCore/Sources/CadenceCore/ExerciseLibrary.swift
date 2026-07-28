import Foundation

/// A seedable, searchable catalog of exercises (field-testing §03). Each entry
/// carries equipment, mechanics, force, and muscle facets (exrx-structured,
/// original data) so search resolves "cable", "lats", "push", etc. Custom
/// exercises created by the user are stored alongside these in SwiftData.
public struct ExerciseTemplate: Equatable, Sendable, Identifiable, ExerciseSearchable {
    public var name: String
    public var category: ExerciseCategory
    public var equipment: Equipment?
    public var force: Force?
    public var mechanics: Mechanics
    public var isLateral: Bool
    public var primaryMuscles: [String]
    public var secondaryMuscles: [String]
    // P2 (CC0 library): public-domain facets from free-exercise-db. All optional/
    // defaulted so the curated literal catalog and CloudKit stay source-compatible.
    public var instructions: [String]
    public var imageName: String?
    public var level: String?

    public var id: String { name }
    public var isCustom: Bool { false }
    /// Legacy flat tags (kept for back-compat).
    public var muscleGroups: [String] { primaryMuscles + secondaryMuscles }
    /// Derived search tokens (not stored; computed from facets).
    public var searchKeywords: [String] {
        ExerciseSearch.keywords(name: name, equipment: equipment, isLateral: isLateral,
                                force: force, mechanics: mechanics,
                                primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles)
    }

    /// Concise positional initializer for the literal catalog.
    public init(_ name: String, _ category: ExerciseCategory, _ equipment: Equipment?,
                _ force: Force?, _ mechanics: Mechanics,
                primary: [String], secondary: [String] = [], lateral: Bool = false,
                instructions: [String] = [], imageName: String? = nil, level: String? = nil) {
        self.name = name
        self.category = category
        self.equipment = equipment
        self.force = force
        self.mechanics = mechanics
        self.isLateral = lateral
        self.primaryMuscles = primary
        self.secondaryMuscles = secondary
        self.instructions = instructions
        self.imageName = imageName
        self.level = level
    }
}

public enum ExerciseLibrary {

    /// Built-in catalog seeded on first launch and version-upgraded thereafter.
    /// Bump `seedVersion` when entries are added so existing stores backfill.
    public static let seedVersion = 8

    /// Our hand-curated catalog — the authoritative facet source (our muscle ids,
    /// movement-split categories, the "popular" shortlist all reference these).
    public static let curated: [ExerciseTemplate] = chest + back + shoulders
        + arms + legs + glutes + core + olympicAndCarry + crossfit + bodyweight
        + plyometrics + accessories

    /// The full seeded catalog: curated entries plus every public-domain
    /// free-exercise-db movement not already covered by name (P2). Curated facets
    /// win on a name collision — we trust our `MuscleCatalog` mapping over their
    /// coarser strings.
    public static let starter: [ExerciseTemplate] = {
        let importedByName = Dictionary(
            ImportedExerciseLibrary.templates.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { a, _ in a }
        )
        let importedByID = Dictionary(
            ImportedExerciseLibrary.templates.compactMap { t -> (String, ExerciseTemplate)? in
                guard let id = t.imageName else { return nil }
                return (id, t)
            },
            uniquingKeysWith: { a, _ in a }
        )
        var merged = curated.map { t -> ExerciseTemplate in
            var imp = importedByName[t.name.lowercased()]
            if imp == nil, let aliasID = curatedAlias[t.name.lowercased()] {
                imp = importedByID[aliasID]
            }
            guard let imp else { return t }
            var enriched = t
            if enriched.instructions.isEmpty { enriched.instructions = imp.instructions }
            if enriched.imageName == nil { enriched.imageName = imp.imageName }
            if enriched.level == nil { enriched.level = imp.level }
            return enriched
        }
        var seen = Set(curated.map { $0.name.lowercased() })
        for t in ImportedExerciseLibrary.templates where seen.insert(t.name.lowercased()).inserted {
            merged.append(t)
        }
        // Final safety net: collapse singular/plural & punctuation variants that
        // escape the exact-name + alias dedup above (e.g. curated "Handstand Push-Up"
        // stub vs imported "Handstand Push-Ups"). The first occurrence wins — curated
        // entries lead `merged`, so our canonical name + hand-mapped facets survive —
        // and we backfill its missing instructions/image/level from the dropped twin.
        return collapseVariants(merged)
    }()

    /// Collapses catalog entries whose names are the same movement written slightly
    /// differently (plural, hyphen). Keeps the first entry per `dedupKey`, enriched
    /// with any instructions/image/level the later duplicates carry.
    static func collapseVariants(_ templates: [ExerciseTemplate]) -> [ExerciseTemplate] {
        var byKey: [String: Int] = [:]
        var deduped: [ExerciseTemplate] = []
        for t in templates {
            let key = dedupKey(t.name)
            if let idx = byKey[key] {
                var survivor = deduped[idx]
                if survivor.instructions.isEmpty { survivor.instructions = t.instructions }
                if survivor.imageName == nil { survivor.imageName = t.imageName }
                if survivor.level == nil { survivor.level = t.level }
                deduped[idx] = survivor
            } else {
                byKey[key] = deduped.count
                deduped.append(t)
            }
        }
        return deduped
    }

    /// Canonical key for detecting "same movement, different spelling" duplicates:
    /// lowercased, hyphens→spaces, punctuation stripped, whitespace collapsed, and a
    /// single trailing plural "s" dropped. Shared by the catalog dedup and the
    /// store-migration that collapses already-seeded duplicate rows.
    public static func dedupKey(_ name: String) -> String {
        var s = name.lowercased().replacingOccurrences(of: "-", with: " ")
        s = String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " })
        s = s.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        if s.hasSuffix("s") { s = String(s.dropLast()) }
        return s
    }

    static let curatedAlias: [String: String] = [
        "bench press": "Barbell_Bench_Press_-_Medium_Grip",
        "incline bench press": "Barbell_Incline_Bench_Press_-_Medium_Grip",
        "back squat": "Barbell_Squat",
        "deadlift": "Barbell_Deadlift",
        "overhead press": "Standing_Military_Press",
        "barbell row": "Bent_Over_Barbell_Row",
        "pull-up": "Pullups",
        "dip": "Dips_-_Chest_Version",
        "push-up": "Pushups",
        "lat pulldown": "Wide-Grip_Lat_Pulldown",
        "cable fly": "Flat_Bench_Cable_Flyes",
        "front squat": "Front_Squat_Clean_Grip",
        "standing calf raise": "Standing_Calf_Raises",
        "dumbbell lateral raise": "Side_Lateral_Raise",
        "seated cable row": "Seated_Cable_Rows",
        "seated dumbbell shoulder press": "Seated_Dumbbell_Press",
        "arnold press": "Arnold_Dumbbell_Press",
        "cable lateral raise": "Cable_Seated_Lateral_Raise",
        "back extension": "Hyperextensions_Back_Extensions",
        "pike push-up": "Push-Ups_With_Feet_Elevated",
        "close-grip lat pulldown": "Close-Grip_Front_Lat_Pulldown",
        "dumbbell fly": "Dumbbell_Flyes",
        "incline dumbbell fly": "Incline_Dumbbell_Flyes",
        "t-bar row": "T-Bar_Row_with_Handle",
        "hammer curl": "Hammer_Curls",
        "lying leg curl": "Lying_Leg_Curls",
        "leg extension": "Leg_Extensions",
        "incline dumbbell bench press": "Incline_Dumbbell_Press",
        "rack pull": "Rack_Pulls",
        "machine chest press": "Leverage_Chest_Press",
        "smith machine bench press": "Smith_Machine_Bench_Press",
        "air squat": "Bodyweight_Squat",
        "bulgarian split squat": "Split_Squats",
        "glute bridge": "Pelvic_Tilt_Into_Bridge",
        // Phase 2: zombie-exercise enrichments (curated name → free-exercise-db ID)
        "ab wheel rollout": "Ab_Roller",
        "box jump": "Box_Jump_Multiple_Response",
        "cable curl": "Standing_Biceps_Cable_Curl",
        "cable hammer curl": "Cable_Hammer_Curls_-_Rope_Attachment",
        "close-grip bench press": "Close-Grip_Barbell_Bench_Press",
        "depth jump": "Depth_Jump_Leap",
        "dumbbell curl": "Dumbbell_Bicep_Curl",
        "dumbbell pullover": "Bent-Arm_Dumbbell_Pullover",
        "farmer's carry": "Farmers_Walk",
        "hip thrust": "Barbell_Hip_Thrust",
        "jump squat": "Freehand_Jump_Squat",
        "kettlebell clean": "Two-Arm_Kettlebell_Clean",
        "landmine press": "Landmine_Linear_Jammer",
        "medicine ball slam": "One-Arm_Medicine_Ball_Slam",
        "pec deck": "Butterfly",
        "pistol squat": "Kettlebell_Pistol_Squat",
        "rear delt fly": "Cable_Rear_Delt_Fly",
        "reverse curl": "Standing_Dumbbell_Reverse_Curl",
        "rowing machine": "Rowing_Stationary",
        "skull crusher": "Band_Skull_Crusher",
        "step-up": "Step-up_with_Knee_Raise",
        "stiff-leg deadlift": "Stiff-Legged_Barbell_Deadlift",
        "thruster": "Kettlebell_Thruster",
        "tuck jump": "Knee_Tuck_Jump",
        "turkish get-up": "Kettlebell_Turkish_Get-Up_Lunge_style",
        "walking lunge": "Barbell_Walking_Lunge",
        "wrist curl": "Cable_Wrist_Curl",
    ]

    // MARK: Chest
    private static let chest: [ExerciseTemplate] = [
        .init("Bench Press", .push, .barbell, .push, .compound, primary: ["chest"], secondary: ["triceps", "front-delts"]),
        .init("Incline Bench Press", .push, .barbell, .push, .compound, primary: ["upper-chest", "chest"], secondary: ["front-delts", "triceps"]),
        .init("Decline Barbell Bench Press", .push, .barbell, .push, .compound, primary: ["chest"], secondary: ["triceps"]),
        .init("Dumbbell Bench Press", .push, .dumbbell, .push, .compound, primary: ["chest"], secondary: ["triceps", "front-delts"]),
        .init("Incline Dumbbell Bench Press", .push, .dumbbell, .push, .compound, primary: ["upper-chest", "chest"], secondary: ["front-delts"]),
        .init("Dumbbell Fly", .push, .dumbbell, .push, .isolation, primary: ["chest"]),
        .init("Incline Dumbbell Fly", .push, .dumbbell, .push, .isolation, primary: ["upper-chest", "chest"]),
        .init("Cable Fly", .push, .cable, .push, .isolation, primary: ["chest"]),
        .init("Cable Crossover", .push, .cable, .push, .isolation, primary: ["chest"]),
        .init("Machine Chest Press", .push, .machine, .push, .compound, primary: ["chest"], secondary: ["triceps"]),
        .init("Pec Deck", .push, .machine, .push, .isolation, primary: ["chest"]),
        .init("Machine Fly", .push, .machine, .push, .isolation, primary: ["chest"],
              instructions: ["Sit in the fly machine with back flat against the pad.",
                             "Grasp the handles with arms extended to the sides.",
                             "Squeeze chest to bring handles together in front of you.",
                             "Slowly return to starting position."]),
        .init("Smith Machine Bench Press", .push, .smith, .push, .compound, primary: ["chest"], secondary: ["triceps"]),
        .init("Push-Up", .push, .bodyweight, .push, .compound, primary: ["chest"], secondary: ["triceps", "front-delts"]),
        .init("Incline Push-Up", .push, .bodyweight, .push, .compound, primary: ["chest"], secondary: ["triceps"]),
        .init("Dip", .push, .bodyweight, .push, .compound, primary: ["chest"], secondary: ["triceps", "front-delts"]),
    ]

    // MARK: Back
    private static let back: [ExerciseTemplate] = [
        .init("Deadlift", .pull, .barbell, .pull, .compound, primary: ["lower-back", "glutes", "hamstrings"], secondary: ["traps", "lats"]),
        .init("Barbell Row", .pull, .barbell, .pull, .compound, primary: ["lats", "rhomboids"], secondary: ["biceps", "rear-delts"]),
        .init("T-Bar Row", .pull, .barbell, .pull, .compound, primary: ["lats", "rhomboids"], secondary: ["biceps"]),
        .init("Pull-Up", .pull, .bodyweight, .pull, .compound, primary: ["lats"], secondary: ["biceps", "rhomboids"]),
        .init("Chin-Up", .pull, .bodyweight, .pull, .compound, primary: ["lats", "biceps"], secondary: ["rhomboids"]),
        .init("Lat Pulldown", .pull, .cable, .pull, .compound, primary: ["lats"], secondary: ["biceps"]),
        .init("Close-Grip Lat Pulldown", .pull, .cable, .pull, .compound, primary: ["lats"], secondary: ["biceps"]),
        .init("Straight-Arm Pulldown", .pull, .cable, .pull, .isolation, primary: ["lats"]),
        .init("Seated Cable Row", .pull, .cable, .pull, .compound, primary: ["rhomboids", "lats"], secondary: ["biceps"]),
        .init("Inverted Row", .pull, .bodyweight, .pull, .compound, primary: ["rhomboids", "lats"], secondary: ["biceps"]),
        .init("Back Extension", .pull, .bodyweight, .pull, .isolation, primary: ["lower-back"], secondary: ["glutes", "hamstrings"]),
        .init("Rack Pull", .pull, .barbell, .pull, .compound, primary: ["lower-back", "traps"], secondary: ["lats", "glutes"]),
        .init("Chest-Supported Machine Row", .pull, .machine, .pull, .compound, primary: ["rhomboids", "lats"], secondary: ["biceps", "rear-delts"],
              instructions: ["Adjust chest pad so arms are fully extended in starting position.",
                             "Grasp handles with palms facing in or down.",
                             "Pull handles toward you, squeezing shoulder blades together.",
                             "Slowly return to full extension."]),
        .init("Machine Lat Pulldown", .pull, .machine, .pull, .compound, primary: ["lats"], secondary: ["biceps"],
              instructions: ["Sit at the machine with thighs secured under the pad.",
                             "Grasp the handles above you with a wide grip.",
                             "Pull the handles down to your upper chest, squeezing lats.",
                             "Control the return to the start position."]),
    ]

    // MARK: Shoulders
    private static let shoulders: [ExerciseTemplate] = [
        .init("Overhead Press", .push, .barbell, .push, .compound, primary: ["delts", "front-delts"], secondary: ["triceps"]),
        .init("Push Press", .push, .barbell, .push, .compound, primary: ["delts"], secondary: ["triceps", "quads"]),
        .init("Seated Dumbbell Shoulder Press", .push, .dumbbell, .push, .compound, primary: ["delts", "front-delts"], secondary: ["triceps"]),
        .init("Arnold Press", .push, .dumbbell, .push, .compound, primary: ["delts", "front-delts"], secondary: ["triceps"]),
        .init("Dumbbell Lateral Raise", .push, .dumbbell, .push, .isolation, primary: ["delts"]),
        .init("Cable Lateral Raise", .push, .cable, .push, .isolation, primary: ["delts"], lateral: true),
        .init("Rear Delt Fly", .pull, .dumbbell, .pull, .isolation, primary: ["rear-delts"]),
        .init("Face Pull", .pull, .cable, .pull, .isolation, primary: ["rear-delts"], secondary: ["traps"]),
        .init("Barbell Shrug", .pull, .barbell, .pull, .isolation, primary: ["traps"]),
        .init("Dumbbell Shrug", .pull, .dumbbell, .pull, .isolation, primary: ["traps"]),
        .init("Machine Shoulder Press", .push, .machine, .push, .compound, primary: ["delts", "front-delts"], secondary: ["triceps"],
              instructions: ["Sit in the shoulder press machine with back flat against the pad.",
                             "Grasp handles at shoulder height with palms facing forward.",
                             "Press handles overhead until arms are fully extended.",
                             "Lower handles back to shoulder level with control."]),
        .init("Machine Lateral Raise", .push, .machine, .push, .isolation, primary: ["delts"],
              instructions: ["Sit in the lateral raise machine with arms resting on the pads.",
                             "Position elbows at roughly 90 degrees against the pads.",
                             "Raise arms out to the sides until they reach shoulder height.",
                             "Slowly lower back to the starting position."]),
        .init("Machine Reverse Fly", .pull, .machine, .pull, .isolation, primary: ["rear-delts"],
              instructions: ["Sit facing the machine with chest against the pad.",
                             "Grasp the handles with arms extended forward.",
                             "Pull the handles outward and back, squeezing rear delts.",
                             "Slowly return to the starting position."]),
    ]

    // MARK: Arms
    private static let arms: [ExerciseTemplate] = [
        .init("Barbell Curl", .pull, .barbell, .pull, .isolation, primary: ["biceps"]),
        .init("EZ-Bar Curl", .pull, .barbell, .pull, .isolation, primary: ["biceps"]),
        .init("Dumbbell Curl", .pull, .dumbbell, .pull, .isolation, primary: ["biceps"]),
        .init("Hammer Curl", .pull, .dumbbell, .pull, .isolation, primary: ["biceps", "forearms"]),
        .init("Incline Dumbbell Curl", .pull, .dumbbell, .pull, .isolation, primary: ["biceps"]),
        .init("Concentration Curl", .pull, .dumbbell, .pull, .isolation, primary: ["biceps"], lateral: true),
        .init("Cable Curl", .pull, .cable, .pull, .isolation, primary: ["biceps"]),
        .init("Preacher Curl", .pull, .machine, .pull, .isolation, primary: ["biceps"]),
        .init("Machine Bicep Curl", .pull, .machine, .pull, .isolation, primary: ["biceps"],
              instructions: ["Sit at the bicep curl machine with elbows resting on the pad.",
                             "Grasp the handles with palms facing up.",
                             "Curl handles toward your shoulders, squeezing biceps at the top.",
                             "Slowly lower back to the starting position."]),
        .init("Machine Triceps Extension", .push, .machine, .push, .isolation, primary: ["triceps"],
              instructions: ["Sit in the triceps machine with back flat against the pad.",
                             "Grasp handles with arms bent at 90 degrees.",
                             "Push handles down until arms are fully extended.",
                             "Slowly return to the starting position."]),
        .init("Seated Dip Machine", .push, .machine, .push, .compound, primary: ["triceps"], secondary: ["chest"],
              instructions: ["Sit in the dip machine with back against the pad.",
                             "Grasp the parallel handles at your sides.",
                             "Press down until arms are fully extended.",
                             "Slowly return to the starting position."]),
        .init("Triceps Pushdown", .push, .cable, .push, .isolation, primary: ["triceps"]),
        .init("Skull Crusher", .push, .barbell, .push, .isolation, primary: ["triceps"]),
        .init("Close-Grip Bench Press", .push, .barbell, .push, .compound, primary: ["triceps"], secondary: ["chest"]),
        .init("Bench Dip", .push, .bodyweight, .push, .compound, primary: ["triceps"], secondary: ["chest"]),
        .init("Wrist Curl", .pull, .dumbbell, .pull, .isolation, primary: ["forearms"]),
        .init("Reverse Curl", .pull, .barbell, .pull, .isolation, primary: ["forearms", "biceps"]),
    ]

    // MARK: Legs
    private static let legs: [ExerciseTemplate] = [
        .init("Back Squat", .legs, .barbell, .push, .compound, primary: ["quads", "glutes"], secondary: ["hamstrings", "lower-back"]),
        .init("Front Squat", .legs, .barbell, .push, .compound, primary: ["quads"], secondary: ["glutes"]),
        .init("Smith Machine Squat", .legs, .smith, .push, .compound, primary: ["quads", "glutes"]),
        .init("Goblet Squat", .legs, .dumbbell, .push, .compound, primary: ["quads", "glutes"]),
        .init("Leg Press", .legs, .machine, .push, .compound, primary: ["quads", "glutes"], secondary: ["hamstrings"]),
        .init("Hack Squat", .legs, .machine, .push, .compound, primary: ["quads"], secondary: ["glutes"]),
        .init("Bulgarian Split Squat", .legs, .dumbbell, .push, .compound, primary: ["quads", "glutes"], lateral: true),
        .init("Walking Lunge", .legs, .dumbbell, .push, .compound, primary: ["quads", "glutes"], lateral: true),
        .init("Leg Extension", .legs, .machine, .push, .isolation, primary: ["quads"]),
        .init("Hip Adduction Machine", .legs, .machine, .push, .isolation, primary: ["adductors"],
              instructions: ["Sit in the adduction machine and adjust the thigh pads.",
                             "Position the pads against your inner thighs.",
                             "Squeeze your thighs together against the resistance.",
                             "Slowly return to the starting position."]),
        .init("Hip Abduction Machine", .legs, .machine, .push, .isolation, primary: ["glutes", "abductors"],
              instructions: ["Sit in the abduction machine and adjust the thigh pads.",
                             "Position the pads against your outer thighs.",
                             "Push legs outward against the resistance.",
                             "Slowly return to the starting position."]),
        .init("Romanian Deadlift", .legs, .barbell, .pull, .compound, primary: ["hamstrings", "glutes"], secondary: ["lower-back"]),
        .init("Stiff-Leg Deadlift", .legs, .barbell, .pull, .compound, primary: ["hamstrings"], secondary: ["glutes", "lower-back"]),
        .init("Lying Leg Curl", .legs, .machine, .pull, .isolation, primary: ["hamstrings"]),
        .init("Seated Leg Curl", .legs, .machine, .pull, .isolation, primary: ["hamstrings"]),
        .init("Standing Calf Raise", .legs, .machine, .push, .isolation, primary: ["calves"]),
        .init("Seated Calf Raise", .legs, .machine, .push, .isolation, primary: ["calves"]),
        .init("Box Jump", .legs, .plyometric, .push, .compound, primary: ["quads", "glutes"], secondary: ["calves"]),
        .init("Jump Squat", .legs, .plyometric, .push, .compound, primary: ["quads", "glutes"]),
    ]

    // MARK: Glutes
    private static let glutes: [ExerciseTemplate] = [
        .init("Hip Thrust", .legs, .barbell, .push, .compound, primary: ["glutes"], secondary: ["hamstrings"]),
        .init("Glute Bridge", .legs, .bodyweight, .push, .compound, primary: ["glutes"], secondary: ["hamstrings"]),
        .init("Step-Up", .legs, .dumbbell, .push, .compound, primary: ["glutes", "quads"], lateral: true),
    ]

    // MARK: Core
    private static let core: [ExerciseTemplate] = [
        .init("Plank", .core, .bodyweight, .static, .isolation, primary: ["abs"], secondary: ["obliques"]),
        .init("Hanging Leg Raise", .core, .bodyweight, .pull, .isolation, primary: ["abs", "hip-flexors"]),
        .init("Cable Crunch", .core, .cable, .pull, .isolation, primary: ["abs"]),
        .init("Sit-Up", .core, .bodyweight, .pull, .isolation, primary: ["abs", "hip-flexors"]),
        .init("Russian Twist", .core, .bodyweight, .pull, .isolation, primary: ["obliques"], secondary: ["abs"]),
        .init("Ab Wheel Rollout", .core, .bodyweight, .pull, .compound, primary: ["abs"], secondary: ["lower-back"]),
        .init("Mountain Climber", .core, .bodyweight, .push, .compound, primary: ["abs", "hip-flexors"]),
        .init("Machine Crunch", .core, .machine, .pull, .isolation, primary: ["abs"],
              instructions: ["Sit in the abdominal crunch machine with chest against pad.",
                             "Grasp the handles at chest level.",
                             "Crunch forward, contracting your abs.",
                             "Slowly return to the starting position."]),
    ]

    // MARK: Olympic / carries / full-body
    private static let olympicAndCarry: [ExerciseTemplate] = [
        .init("Power Clean", .pull, .barbell, .pull, .compound, primary: ["traps", "glutes", "quads"], secondary: ["hamstrings", "delts"]),
        .init("Clean and Jerk", .pull, .barbell, .pull, .compound, primary: ["quads", "glutes", "delts"], secondary: ["traps"]),
        .init("Snatch", .pull, .barbell, .pull, .compound, primary: ["quads", "glutes", "delts"], secondary: ["traps", "lower-back"]),
        .init("Kettlebell Clean", .pull, .kettlebell, .pull, .compound, primary: ["glutes", "traps"], secondary: ["quads"], lateral: true),
        .init("Farmer's Carry", .legs, .dumbbell, .static, .compound, primary: ["forearms", "traps"], secondary: ["abs", "quads"]),
        .init("Thruster", .legs, .barbell, .push, .compound, primary: ["quads", "delts"], secondary: ["glutes", "triceps"]),
        .init("Clean and Press", .pull, .barbell, .pull, .compound, primary: ["quads", "glutes", "delts"], secondary: ["triceps", "traps"]),
        .init("Turkish Get-Up", .core, .kettlebell, .push, .compound, primary: ["delts", "abs", "glutes"], secondary: ["quads", "triceps"]),
    ]

    // MARK: CrossFit / functional movements (round4b §B-1)
    // The named movements used by the benchmark "Girls" workouts plus common
    // staples, so they're searchable and usable in custom workouts. Movements
    // already in the catalog (Thruster, Clean and Jerk, Snatch, Power Clean,
    // Kettlebell Swing, Deadlift, Push-Up, Pull-Up, Sit-Up) are reused as-is.
    private static let crossfit: [ExerciseTemplate] = [
        .init("Air Squat", .legs, .bodyweight, .push, .compound, primary: ["quads", "glutes"], secondary: ["hamstrings"]),
        .init("Overhead Squat", .legs, .barbell, .push, .compound, primary: ["quads", "glutes"], secondary: ["delts", "abs"]),
        .init("Pistol Squat", .legs, .bodyweight, .push, .compound, primary: ["quads", "glutes"], secondary: ["hamstrings"], lateral: true),
        .init("Clean", .pull, .barbell, .pull, .compound, primary: ["quads", "glutes", "traps"], secondary: ["hamstrings", "delts"]),
        .init("Handstand Push-Up", .push, .bodyweight, .push, .compound, primary: ["delts", "triceps"], secondary: ["traps"]),
        .init("Ring Dip", .push, .bodyweight, .push, .compound, primary: ["triceps", "chest"], secondary: ["front-delts"]),
        .init("Muscle-Up", .pull, .bodyweight, .pull, .compound, primary: ["lats", "triceps"], secondary: ["chest", "biceps"]),
        .init("Rowing Machine", .cardio, .machine, .pull, .compound, primary: ["lats", "quads"], secondary: ["biceps", "hamstrings"]),
    ]

    // MARK: Bodyweight / calisthenics (feedback batch 3)
    // The popular bodyweight movements a lifter reaches for when training without
    // load. Movements already present (Push-Up, Pull-Up, Chin-Up, Dip, Air Squat,
    // Pistol Squat, Inverted Row, Glute Bridge, Plank, Side Plank, Sit-Up, Crunch,
    // Hanging Leg Raise, Bench Dip, Mountain Climber, Burpee, Handstand Push-Up,
    // Ring Dip, Muscle-Up, Nordic Curl) are reused as-is. All `.bodyweight`.
    private static let bodyweight: [ExerciseTemplate] = [
        .init("Pike Push-Up", .push, .bodyweight, .push, .compound, primary: ["delts"], secondary: ["triceps", "front-delts"]),
        .init("Decline Push-Up", .push, .bodyweight, .push, .compound, primary: ["upper-chest", "chest"], secondary: ["triceps", "front-delts"]),
        .init("Single-Leg Glute Bridge", .legs, .bodyweight, .push, .compound, primary: ["glutes"], secondary: ["hamstrings"], lateral: true),
        .init("Superman", .core, .bodyweight, .pull, .isolation, primary: ["lower-back"], secondary: ["glutes"]),
        .init("Flutter Kick", .core, .bodyweight, .pull, .isolation, primary: ["abs", "hip-flexors"]),
    ]

    // MARK: Plyometrics (feedback batch 8)
    // Explosive/jump training as its own category. Box Jump / Jump Squat /
    // Plyometric Push-Up / Double-Under already exist above (kept in their movement
    // categories); these are dedicated plyo movements.
    private static let plyometrics: [ExerciseTemplate] = [
        .init("Depth Jump", .plyometrics, .plyometric, .push, .compound, primary: ["quads", "glutes"], secondary: ["calves"]),
        .init("Tuck Jump", .plyometrics, .plyometric, .push, .compound, primary: ["quads", "glutes"], secondary: ["calves", "hip-flexors"]),
        .init("Lateral Bound", .plyometrics, .plyometric, .push, .compound, primary: ["glutes", "quads"], secondary: ["abductors", "calves"], lateral: true),
        .init("Medicine Ball Slam", .plyometrics, .plyometric, .pull, .compound, primary: ["abs", "lats"], secondary: ["delts"]),
        .init("Medicine Ball Chest Pass", .plyometrics, .plyometric, .push, .compound, primary: ["chest"], secondary: ["triceps", "front-delts"]),
    ]

    // MARK: Accessories (feedback batch 8) — broadens coverage per body part.
    private static let accessories: [ExerciseTemplate] = [
        .init("Good Morning", .legs, .barbell, .pull, .compound, primary: ["hamstrings", "lower-back"], secondary: ["glutes"]),
        .init("Landmine Press", .push, .barbell, .push, .compound, primary: ["delts", "upper-chest"], secondary: ["triceps"], lateral: true),
        .init("Dead Bug", .core, .bodyweight, .static, .isolation, primary: ["abs"], secondary: ["hip-flexors"]),
        .init("Zottman Curl", .pull, .dumbbell, .pull, .isolation, primary: ["biceps", "forearms"]),
        .init("Cable Hammer Curl", .pull, .cable, .pull, .isolation, primary: ["biceps", "forearms"]),
        .init("JM Press", .push, .barbell, .push, .compound, primary: ["triceps"], secondary: ["chest"]),
        .init("Cable Rear Delt Fly", .pull, .cable, .pull, .isolation, primary: ["rear-delts"], lateral: true),
        .init("Dumbbell Pullover", .push, .dumbbell, .push, .compound, primary: ["chest", "lats"], secondary: ["triceps"]),
    ]

    /// Ranked, keyword-aware search (field-testing §03).
    public static func search(_ query: String, in templates: [ExerciseTemplate]) -> [ExerciseTemplate] {
        ExerciseSearch.rank(query, over: templates)
    }

    /// Case-insensitive lookup of a built-in template by canonical name.
    public static let byName: [String: ExerciseTemplate] =
        Dictionary(starter.map { (lookupKey($0.name), $0) }, uniquingKeysWith: { a, _ in a })

    /// Common names users type or carry over from older app lists. These are still
    /// built-ins; resolving them here prevents empty "custom" duplicates from
    /// being created by watch sync or import-by-name paths.
    public static let commonNameAliases: [String: String] = [
        "lateral raise": "Dumbbell Lateral Raise",
        "dumbell lateral raise": "Dumbbell Lateral Raise",
        "tricep pushdown": "Triceps Pushdown",
        "tricep pressdown": "Triceps Pushdown",
        "triceps pressdown": "Triceps Pushdown",
        "cable tricep pushdown": "Triceps Pushdown",
        "cable triceps pushdown": "Triceps Pushdown",
    ]

    private static let byDedupKey: [String: ExerciseTemplate] =
        Dictionary(starter.map { (dedupKey($0.name), $0) }, uniquingKeysWith: { a, _ in a })

    public static func lookupKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Resolves canonical built-in names plus known aliases and simple spelling
    /// variants. Returns nil only when the name truly has no built-in equivalent.
    public static func template(matching name: String) -> ExerciseTemplate? {
        let key = lookupKey(name)
        if let exact = byName[key] { return exact }
        if let canonical = commonNameAliases[key],
           let alias = byName[lookupKey(canonical)] {
            return alias
        }
        return byDedupKey[dedupKey(name)]
    }

    /// Builds a SwiftData `Exercise` from a template, deriving search keywords
    /// and load accounting defaults.
    public static func makeExercise(from t: ExerciseTemplate) -> Exercise {
        Exercise(name: t.name, category: t.category, muscleGroups: t.muscleGroups,
                 isCustom: false, equipment: t.equipment, isLateral: t.isLateral,
                 mechanics: t.mechanics, force: t.force,
                 primaryMuscles: t.primaryMuscles, secondaryMuscles: t.secondaryMuscles,
                 searchKeywords: t.searchKeywords,
                 instructions: t.instructions, imageName: t.imageName, level: t.level,
                 loadAccountingMode: Exercise.defaultLoadAccountingMode(equipment: t.equipment,
                                                                         isLateral: t.isLateral,
                                                                         name: t.name),
                 defaultBarWeightKg: t.equipment == .barbell ? Exercise.defaultBarWeightKg : 0)
    }
}
