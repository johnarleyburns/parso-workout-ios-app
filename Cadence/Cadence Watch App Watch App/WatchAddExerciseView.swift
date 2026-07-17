import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchAddExerciseView: View {
    let model: WatchStrengthFlowModel

    var body: some View {
        List {
            ForEach(commonExercises, id: \.self) { name in
                Button {
                    model.addExercise(named: name)
                } label: {
                    Text(name)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Add Exercise")
    }

    private let commonExercises: [String] = [
        "Bench Press", "Squat", "Deadlift", "Overhead Press", "Row",
        "Pull-Up", "Bicep Curl", "Tricep Extension", "Lunges", "Leg Press",
        "Lat Pulldown", "Shoulder Press", "Dumbbell Fly", "Calf Raise", "Plank"
    ]
}
