import SwiftUI
import SwiftData
import CadenceCore

struct WatchSuggestedExerciseInfoView: View {
    let name: String
    @Environment(\.modelContext) private var context
    @State private var exercise: Exercise?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            if let exercise {
                WatchExerciseDetailContent(exercise: exercise)
            } else if loaded {
                Text("Exercise details unavailable. Sync your library and try again.")
                    .font(.footnote)
            } else {
                ProgressView("Loading details…")
            }
        }
        .navigationTitle(name)
        .task(id: name) {
            let key = ExerciseLibrary.dedupKey(name)
            exercise = (try? WorkoutRepository.allExercises(context))?.first {
                ExerciseLibrary.dedupKey($0.name) == key
            }
            loaded = true
        }
    }
}
