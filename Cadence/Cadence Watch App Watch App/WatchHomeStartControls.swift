import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

extension WatchRootView {
    /// One scrollable-list row per phone workout choice. Tapping a row both
    /// selects and launches it; the parent `List` owns the scrolling.
    @ViewBuilder
    func homeWorkoutChoiceRows(selection: Binding<WatchHomeWorkoutSelection>) -> some View {
        ForEach(selection.wrappedValue.choices) { option in
            Button {
                WatchHaptics.tap()
                selection.wrappedValue.selectAndStart(option)
                selection.wrappedValue.persist()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: option.symbol)
                        .foregroundStyle(.tint)
                        .frame(width: 22)
                    Text(LocalizedStringKey(option.title))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("watch.workoutChoice.\(option.id)")
            .accessibilityHint("Starts or opens \(option.title)")
        }
    }
}

/// Attach outside the List's lazy rows so navigation destinations are always
/// registered, and the home toolbar stays anchored to the screen corners.
struct WatchHomeStartNavigation: ViewModifier {
    @Binding var selection: WatchHomeWorkoutSelection
    let cardioDestination: (CardioType) -> AnyView
    let suggestedCardioDestination: () -> AnyView

    func body(content: Content) -> some View {
        content
        .navigationDestination(item: Binding(
            get: { selection.launchChoice },
            set: { if $0 == nil { selection.dismissStart() } })) { choice in
                destination(for: choice)
            }
    }

    @ViewBuilder
    private func destination(for choice: HomeWorkoutStartChoice) -> some View {
        switch choice {
        case .strength(.quickStart):
            WatchStrengthPreview(launch: WatchLiftLaunch(title: "Custom Strength", exerciseNames: [], repLadder: []))
        case .strength(.suggested):
            WatchHomeSuggestedStrengthView()
        case .strength(.previous):
            WatchPreviousListView()
        case .cardio(let type):
            if let cardio = type.cardioType { cardioDestination(cardio) }
        case .suggestedCardio:
            suggestedCardioDestination()
        }
    }
}
