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
                primary: [String], secondary: [String] = [], lateral: Bool = false) {
        self.name = name
        self.category = category
        self.equipment = equipment
        self.force = force
        self.mechanics = mechanics
        self.isLateral = lateral
        self.primaryMuscles = primary
        self.secondaryMuscles = secondary
    }
}

public enum ExerciseLibrary {

    /// Built-in catalog seeded on first launch and version-upgraded thereafter.
    /// Bump `seedVersion` when entries are added so existing stores backfill.
    public static let seedVersion = 3

    public static let starter: [ExerciseTemplate] = chest + back + shoulders
        + arms + legs + glutes + core + olympicAndCarry + crossfit

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
        .init("Low Cable Fly", .push, .cable, .push, .isolation, primary: ["upper-chest", "chest"]),
        .init("High Cable Fly", .push, .cable, .push, .isolation, primary: ["chest"]),
        .init("Cable Crossover", .push, .cable, .push, .isolation, primary: ["chest"]),
        .init("Single-Arm Cable Press", .push, .cable, .push, .compound, primary: ["chest"], secondary: ["triceps"], lateral: true),
        .init("Machine Chest Press", .push, .machine, .push, .compound, primary: ["chest"], secondary: ["triceps"]),
        .init("Pec Deck", .push, .machine, .push, .isolation, primary: ["chest"]),
        .init("Smith Machine Bench Press", .push, .smith, .push, .compound, primary: ["chest"], secondary: ["triceps"]),
        .init("Push-Up", .push, .bodyweight, .push, .compound, primary: ["chest"], secondary: ["triceps", "front-delts"]),
        .init("Incline Push-Up", .push, .bodyweight, .push, .compound, primary: ["chest"], secondary: ["triceps"]),
        .init("Dip", .push, .bodyweight, .push, .compound, primary: ["chest"], secondary: ["triceps", "front-delts"]),
        .init("Plyometric Push-Up", .push, .plyometric, .push, .compound, primary: ["chest"], secondary: ["triceps"]),
        .init("Banded Chest Press", .push, .band, .push, .compound, primary: ["chest"], secondary: ["triceps"]),
    ]

    // MARK: Back
    private static let back: [ExerciseTemplate] = [
        .init("Deadlift", .pull, .barbell, .pull, .compound, primary: ["lower-back", "glutes", "hamstrings"], secondary: ["traps", "lats"]),
        .init("Barbell Row", .pull, .barbell, .pull, .compound, primary: ["lats", "rhomboids"], secondary: ["biceps", "rear-delts"]),
        .init("Pendlay Row", .pull, .barbell, .pull, .compound, primary: ["lats", "rhomboids"], secondary: ["biceps"]),
        .init("T-Bar Row", .pull, .barbell, .pull, .compound, primary: ["lats", "rhomboids"], secondary: ["biceps"]),
        .init("Pull-Up", .pull, .bodyweight, .pull, .compound, primary: ["lats"], secondary: ["biceps", "rhomboids"]),
        .init("Chin-Up", .pull, .bodyweight, .pull, .compound, primary: ["lats", "biceps"], secondary: ["rhomboids"]),
        .init("Lat Pulldown", .pull, .cable, .pull, .compound, primary: ["lats"], secondary: ["biceps"]),
        .init("Close-Grip Lat Pulldown", .pull, .cable, .pull, .compound, primary: ["lats"], secondary: ["biceps"]),
        .init("Straight-Arm Pulldown", .pull, .cable, .pull, .isolation, primary: ["lats"]),
        .init("Seated Cable Row", .pull, .cable, .pull, .compound, primary: ["rhomboids", "lats"], secondary: ["biceps"]),
        .init("Single-Arm Dumbbell Row", .pull, .dumbbell, .pull, .compound, primary: ["lats", "rhomboids"], secondary: ["biceps"], lateral: true),
        .init("Chest-Supported Dumbbell Row", .pull, .dumbbell, .pull, .compound, primary: ["rhomboids", "lats"], secondary: ["rear-delts"]),
        .init("Machine Row", .pull, .machine, .pull, .compound, primary: ["lats", "rhomboids"], secondary: ["biceps"]),
        .init("Single-Arm Machine Row", .pull, .machine, .pull, .compound, primary: ["lats", "rhomboids"], secondary: ["biceps"], lateral: true),
        .init("Inverted Row", .pull, .bodyweight, .pull, .compound, primary: ["rhomboids", "lats"], secondary: ["biceps"]),
        .init("Banded Row", .pull, .band, .pull, .compound, primary: ["lats", "rhomboids"], secondary: ["biceps"]),
        .init("Back Extension", .pull, .bodyweight, .pull, .isolation, primary: ["lower-back"], secondary: ["glutes", "hamstrings"]),
        .init("Rack Pull", .pull, .barbell, .pull, .compound, primary: ["lower-back", "traps"], secondary: ["lats", "glutes"]),
    ]

    // MARK: Shoulders
    private static let shoulders: [ExerciseTemplate] = [
        .init("Overhead Press", .push, .barbell, .push, .compound, primary: ["delts", "front-delts"], secondary: ["triceps"]),
        .init("Push Press", .push, .barbell, .push, .compound, primary: ["delts"], secondary: ["triceps", "quads"]),
        .init("Seated Dumbbell Shoulder Press", .push, .dumbbell, .push, .compound, primary: ["delts", "front-delts"], secondary: ["triceps"]),
        .init("Arnold Press", .push, .dumbbell, .push, .compound, primary: ["delts", "front-delts"], secondary: ["triceps"]),
        .init("Dumbbell Lateral Raise", .push, .dumbbell, .push, .isolation, primary: ["delts"]),
        .init("Cable Lateral Raise", .push, .cable, .push, .isolation, primary: ["delts"], lateral: true),
        .init("Machine Lateral Raise", .push, .machine, .push, .isolation, primary: ["delts"]),
        .init("Dumbbell Front Raise", .push, .dumbbell, .push, .isolation, primary: ["front-delts"]),
        .init("Rear Delt Fly", .pull, .dumbbell, .pull, .isolation, primary: ["rear-delts"]),
        .init("Reverse Pec Deck", .pull, .machine, .pull, .isolation, primary: ["rear-delts"]),
        .init("Face Pull", .pull, .cable, .pull, .isolation, primary: ["rear-delts"], secondary: ["traps"]),
        .init("Machine Shoulder Press", .push, .machine, .push, .compound, primary: ["delts"], secondary: ["triceps"]),
        .init("Barbell Shrug", .pull, .barbell, .pull, .isolation, primary: ["traps"]),
        .init("Dumbbell Shrug", .pull, .dumbbell, .pull, .isolation, primary: ["traps"]),
        .init("Upright Row", .pull, .barbell, .pull, .compound, primary: ["delts", "traps"], secondary: ["biceps"]),
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
        .init("Banded Curl", .pull, .band, .pull, .isolation, primary: ["biceps"]),
        .init("Triceps Pushdown", .push, .cable, .push, .isolation, primary: ["triceps"]),
        .init("Rope Pushdown", .push, .cable, .push, .isolation, primary: ["triceps"]),
        .init("Overhead Cable Extension", .push, .cable, .push, .isolation, primary: ["triceps"]),
        .init("Skull Crusher", .push, .barbell, .push, .isolation, primary: ["triceps"]),
        .init("Dumbbell Overhead Extension", .push, .dumbbell, .push, .isolation, primary: ["triceps"]),
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
        .init("Romanian Deadlift", .legs, .barbell, .pull, .compound, primary: ["hamstrings", "glutes"], secondary: ["lower-back"]),
        .init("Stiff-Leg Deadlift", .legs, .barbell, .pull, .compound, primary: ["hamstrings"], secondary: ["glutes", "lower-back"]),
        .init("Lying Leg Curl", .legs, .machine, .pull, .isolation, primary: ["hamstrings"]),
        .init("Seated Leg Curl", .legs, .machine, .pull, .isolation, primary: ["hamstrings"]),
        .init("Nordic Curl", .legs, .bodyweight, .pull, .isolation, primary: ["hamstrings"]),
        .init("Standing Calf Raise", .legs, .machine, .push, .isolation, primary: ["calves"]),
        .init("Seated Calf Raise", .legs, .machine, .push, .isolation, primary: ["calves"]),
        .init("Hip Adduction Machine", .legs, .machine, .push, .isolation, primary: ["adductors"]),
        .init("Hip Abduction Machine", .legs, .machine, .push, .isolation, primary: ["abductors"]),
        .init("Box Jump", .legs, .plyometric, .push, .compound, primary: ["quads", "glutes"], secondary: ["calves"]),
        .init("Jump Squat", .legs, .plyometric, .push, .compound, primary: ["quads", "glutes"]),
    ]

    // MARK: Glutes
    private static let glutes: [ExerciseTemplate] = [
        .init("Hip Thrust", .legs, .barbell, .push, .compound, primary: ["glutes"], secondary: ["hamstrings"]),
        .init("Glute Bridge", .legs, .bodyweight, .push, .compound, primary: ["glutes"], secondary: ["hamstrings"]),
        .init("Cable Kickback", .legs, .cable, .push, .isolation, primary: ["glutes"], lateral: true),
        .init("Machine Hip Thrust", .legs, .machine, .push, .compound, primary: ["glutes"], secondary: ["hamstrings"]),
        .init("Step-Up", .legs, .dumbbell, .push, .compound, primary: ["glutes", "quads"], lateral: true),
        .init("Banded Glute Walk", .legs, .band, .push, .isolation, primary: ["glutes", "abductors"]),
    ]

    // MARK: Core
    private static let core: [ExerciseTemplate] = [
        .init("Plank", .core, .bodyweight, .static, .isolation, primary: ["abs"], secondary: ["obliques"]),
        .init("Hanging Leg Raise", .core, .bodyweight, .pull, .isolation, primary: ["abs", "hip-flexors"]),
        .init("Cable Crunch", .core, .cable, .pull, .isolation, primary: ["abs"]),
        .init("Crunch", .core, .bodyweight, .pull, .isolation, primary: ["abs"]),
        .init("Sit-Up", .core, .bodyweight, .pull, .isolation, primary: ["abs", "hip-flexors"]),
        .init("Russian Twist", .core, .bodyweight, .pull, .isolation, primary: ["obliques"], secondary: ["abs"]),
        .init("Ab Wheel Rollout", .core, .bodyweight, .pull, .compound, primary: ["abs"], secondary: ["lower-back"]),
        .init("Machine Crunch", .core, .machine, .pull, .isolation, primary: ["abs"]),
        .init("Side Plank", .core, .bodyweight, .static, .isolation, primary: ["obliques"], lateral: true),
        .init("Mountain Climber", .core, .bodyweight, .push, .compound, primary: ["abs", "hip-flexors"]),
    ]

    // MARK: Olympic / carries / full-body
    private static let olympicAndCarry: [ExerciseTemplate] = [
        .init("Power Clean", .pull, .barbell, .pull, .compound, primary: ["traps", "glutes", "quads"], secondary: ["hamstrings", "delts"]),
        .init("Clean and Jerk", .pull, .barbell, .pull, .compound, primary: ["quads", "glutes", "delts"], secondary: ["traps"]),
        .init("Snatch", .pull, .barbell, .pull, .compound, primary: ["quads", "glutes", "delts"], secondary: ["traps", "lower-back"]),
        .init("Kettlebell Swing", .pull, .kettlebell, .pull, .compound, primary: ["glutes", "hamstrings"], secondary: ["lower-back"]),
        .init("Kettlebell Goblet Squat", .legs, .kettlebell, .push, .compound, primary: ["quads", "glutes"]),
        .init("Kettlebell Clean", .pull, .kettlebell, .pull, .compound, primary: ["glutes", "traps"], secondary: ["quads"], lateral: true),
        .init("Farmer's Carry", .legs, .dumbbell, .static, .compound, primary: ["forearms", "traps"], secondary: ["abs", "quads"]),
        .init("Thruster", .legs, .barbell, .push, .compound, primary: ["quads", "delts"], secondary: ["glutes", "triceps"]),
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
        .init("Box Jump", .legs, .plyometric, .push, .compound, primary: ["quads", "glutes"], secondary: ["calves"]),
        .init("Clean", .pull, .barbell, .pull, .compound, primary: ["quads", "glutes", "traps"], secondary: ["hamstrings", "delts"]),
        .init("Wall Ball", .legs, .bodyweight, .push, .compound, primary: ["quads", "delts"], secondary: ["glutes", "triceps"]),
        .init("Handstand Push-Up", .push, .bodyweight, .push, .compound, primary: ["delts", "triceps"], secondary: ["traps"]),
        .init("Ring Dip", .push, .bodyweight, .push, .compound, primary: ["triceps", "chest"], secondary: ["front-delts"]),
        .init("Muscle-Up", .pull, .bodyweight, .pull, .compound, primary: ["lats", "triceps"], secondary: ["chest", "biceps"]),
        .init("Toes-to-Bar", .core, .bodyweight, .pull, .compound, primary: ["abs", "hip-flexors"], secondary: ["lats"]),
        .init("Burpee", .legs, .bodyweight, .push, .compound, primary: ["quads", "chest"], secondary: ["triceps", "abs"]),
        .init("Double-Under", .cardio, .plyometric, .push, .compound, primary: ["calves"], secondary: ["forearms"]),
        .init("Run", .cardio, nil, nil, .compound, primary: ["quads", "hamstrings", "calves"], secondary: ["glutes"]),
        .init("Rowing Machine", .cardio, .machine, .pull, .compound, primary: ["lats", "quads"], secondary: ["biceps", "hamstrings"]),
    ]

    /// Ranked, keyword-aware search (field-testing §03).
    public static func search(_ query: String, in templates: [ExerciseTemplate]) -> [ExerciseTemplate] {
        ExerciseSearch.rank(query, over: templates)
    }

    /// Case-insensitive lookup of a built-in template by name.
    public static let byName: [String: ExerciseTemplate] =
        Dictionary(starter.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })

    /// Builds a SwiftData `Exercise` from a template, deriving search keywords.
    public static func makeExercise(from t: ExerciseTemplate) -> Exercise {
        Exercise(name: t.name, category: t.category, muscleGroups: t.muscleGroups,
                 isCustom: false, equipment: t.equipment, isLateral: t.isLateral,
                 mechanics: t.mechanics, force: t.force,
                 primaryMuscles: t.primaryMuscles, secondaryMuscles: t.secondaryMuscles,
                 searchKeywords: t.searchKeywords)
    }
}
