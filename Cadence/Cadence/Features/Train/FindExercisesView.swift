import SwiftUI

/// Root of the Find tab: a discovery surface with a large "Find" title. It
/// reuses the picker's catalog/search content in `.find` presentation, which
/// owns the single NavigationStack and has no Cancel or pick completion.
/// Find keeps a normal trailing tab (no `.search` role) so the page keeps its
/// own title; the in-page `.searchable` field provides search.
struct FindExercisesView: View {
    var body: some View {
        ExercisePickerView(action: .use, showsPickAction: false, presentation: .find) { _ in }
    }
}
