import SwiftUI

/// Root of the Find tab: a discovery surface with a large "Find" title that
/// feeds the persistent planning draft without leaving the tab.
struct FindExercisesView: View {
    var body: some View {
        ExercisePickerView(destination: .planningDraft)
    }
}
