import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchAddExerciseView: View {
    let model: WatchStrengthFlowModel

    var body: some View {
        List {
            ForEach(exerciseSections, id: \.category) { section in
                Section(section.category) {
                    ForEach(section.exercises, id: \.self) { name in
                        Button {
                            model.addExercise(named: name)
                        } label: {
                            Text(name)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Add Exercise")
    }

    private let exerciseSections: [ExerciseSection] = [
        ExerciseSection(category: "Chest", exercises: [
            "Bench Press", "Incline Bench Press", "Dumbbell Bench Press",
            "Incline Dumbbell Press", "Cable Fly", "Push-Up"
        ]),
        ExerciseSection(category: "Back", exercises: [
            "Deadlift", "Barbell Row", "Pull-Up", "Chin-Up",
            "Lat Pulldown", "Seated Cable Row", "Dumbbell Row"
        ]),
        ExerciseSection(category: "Shoulders", exercises: [
            "Overhead Press", "Dumbbell Shoulder Press", "Lateral Raise",
            "Front Raise", "Face Pull", "Cable Lateral Raise"
        ]),
        ExerciseSection(category: "Arms", exercises: [
            "Barbell Curl", "Dumbbell Curl", "Hammer Curl",
            "Cable Curl", "Tricep Pushdown", "Overhead Tricep Extension",
            "Skull Crusher", "Tricep Dip"
        ]),
        ExerciseSection(category: "Legs", exercises: [
            "Barbell Squat", "Front Squat", "Goblet Squat",
            "Romanian Deadlift", "Leg Press", "Bulgarian Split Squat",
            "Lunges", "Calf Raise"
        ]),
        ExerciseSection(category: "Core", exercises: [
            "Plank", "Hanging Leg Raise", "Cable Crunch",
            "Russian Twist", "Ab Wheel"
        ]),
        ExerciseSection(category: "Olympic", exercises: [
            "Clean & Jerk", "Snatch", "Push Press"
        ])
    ]
}

private struct ExerciseSection {
    let category: String
    let exercises: [String]
}
