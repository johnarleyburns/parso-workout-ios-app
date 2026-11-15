import SwiftUI
import SwiftData
import CadenceCore

/// Resolve details when opened, rather than hiding the entry point while a
/// parent suggestion's asynchronous catalog index is still loading.
struct SuggestedExerciseInfoView: View {
    let name: String
    var initial: Exercise? = nil
    @Environment(\.modelContext) private var context
    @State private var resolved: Exercise?
    @State private var loaded = false

    var body: some View {
        Group {
            if let exercise = resolved ?? initial {
                ExerciseDetailView(exercise: exercise)
            } else if loaded {
                ContentUnavailableView("Exercise details unavailable", systemImage: "info.circle",
                    description: Text("The exercise is not in the local library. Sync your library and try again."))
            } else {
                ProgressView("Loading exercise details…")
            }
        }
        .task(id: name) {
            let key = ExerciseLibrary.dedupKey(name)
            resolved = (try? WorkoutRepository.allExercises(context))?.first {
                ExerciseLibrary.dedupKey($0.name) == key
            }
            loaded = true
        }
    }
}
