import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Live-workout Add Exercise. The shared picker owns the search-first flow; this
/// wrapper maps adds onto the running `WatchStrengthFlowModel`.
struct WatchAddExerciseView: View {
    let model: WatchStrengthFlowModel

    var body: some View {
        WatchAddExercisePicker(
            existingNames: model.suggestionActiveExerciseNames,
            activeWorkingSets: model.suggestionActiveWorkingSets,
            onAddCatalog: { model.addExercise(id: $0.id, named: $0.name) },
            onAddSuggested: { exercise, entry in
                model.addSuggestedExercise(id: entry.id, name: entry.name,
                                           sets: exercise.plannedSets,
                                           repRange: exercise.repRange)
            },
            onCreateCustom: { name, attribution in
                model.createAndAddExercise(named: name, attribution: attribution)
            },
            onBack: { model.goBackToHome() },
            onAdded: {})
    }
}
