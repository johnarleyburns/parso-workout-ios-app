import SwiftUI
import CadenceFeatures
import CadenceWorkoutFeatures

/// The Progress sections used to be a horizontal chip scroller. They now live
/// in the trailing overflow menu, in the same order, with the current section
/// checked.
struct ProgressSectionMenuButton: View {
    @Binding var selection: ProgressQuestionSelection

    var body: some View {
        Menu {
            ForEach(ProgressSectionMenu.items(for: selection)) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection.select(item.question)
                    }
                } label: {
                    if item.isSelected {
                        Label(item.title, systemImage: "checkmark")
                    } else {
                        Text(item.title)
                    }
                }
                .accessibilityIdentifier(item.accessibilityIdentifier)
                .accessibilityAddTraits(item.isSelected ? .isSelected : [])
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityIdentifier("progress.sectionMenu")
        .accessibilityLabel("Progress section")
    }
}
