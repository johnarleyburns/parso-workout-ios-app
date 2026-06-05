import Foundation

/// A seedable, searchable catalog of common exercises (FR-1.1). Custom
/// exercises created by the user are stored alongside these in SwiftData.
public struct ExerciseTemplate: Equatable, Sendable, Identifiable {
    public var name: String
    public var category: ExerciseCategory
    public var muscleGroups: [String]
    public var id: String { name }

    public init(name: String, category: ExerciseCategory, muscleGroups: [String]) {
        self.name = name
        self.category = category
        self.muscleGroups = muscleGroups
    }
}

public enum ExerciseLibrary {

    /// Built-in starter set seeded on first launch.
    public static let starter: [ExerciseTemplate] = [
        // Push
        .init(name: "Bench Press", category: .push, muscleGroups: ["chest", "triceps", "shoulders"]),
        .init(name: "Incline Bench Press", category: .push, muscleGroups: ["chest", "shoulders"]),
        .init(name: "Overhead Press", category: .push, muscleGroups: ["shoulders", "triceps"]),
        .init(name: "Dumbbell Shoulder Press", category: .push, muscleGroups: ["shoulders"]),
        .init(name: "Dips", category: .push, muscleGroups: ["chest", "triceps"]),
        .init(name: "Triceps Pushdown", category: .push, muscleGroups: ["triceps"]),
        .init(name: "Cable Fly", category: .push, muscleGroups: ["chest"]),
        // Pull
        .init(name: "Deadlift", category: .pull, muscleGroups: ["back", "hamstrings", "glutes"]),
        .init(name: "Barbell Row", category: .pull, muscleGroups: ["back", "biceps"]),
        .init(name: "Pull-Up", category: .pull, muscleGroups: ["back", "biceps"]),
        .init(name: "Lat Pulldown", category: .pull, muscleGroups: ["back", "biceps"]),
        .init(name: "Seated Cable Row", category: .pull, muscleGroups: ["back"]),
        .init(name: "Barbell Curl", category: .pull, muscleGroups: ["biceps"]),
        .init(name: "Face Pull", category: .pull, muscleGroups: ["shoulders", "back"]),
        // Legs
        .init(name: "Back Squat", category: .legs, muscleGroups: ["quads", "glutes"]),
        .init(name: "Front Squat", category: .legs, muscleGroups: ["quads"]),
        .init(name: "Romanian Deadlift", category: .legs, muscleGroups: ["hamstrings", "glutes"]),
        .init(name: "Leg Press", category: .legs, muscleGroups: ["quads", "glutes"]),
        .init(name: "Leg Curl", category: .legs, muscleGroups: ["hamstrings"]),
        .init(name: "Leg Extension", category: .legs, muscleGroups: ["quads"]),
        .init(name: "Calf Raise", category: .legs, muscleGroups: ["calves"]),
        .init(name: "Walking Lunge", category: .legs, muscleGroups: ["quads", "glutes"]),
        // Core
        .init(name: "Plank", category: .core, muscleGroups: ["core"]),
        .init(name: "Hanging Leg Raise", category: .core, muscleGroups: ["core"]),
        .init(name: "Cable Crunch", category: .core, muscleGroups: ["core"]),
    ]

    /// Case- and diacritic-insensitive substring search over a name list.
    public static func search(_ query: String, in templates: [ExerciseTemplate]) -> [ExerciseTemplate] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return templates }
        return templates.filter {
            $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
