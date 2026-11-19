import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

struct WatchHomeStartControls: View {
    @Binding var selection: WatchHomeWorkoutSelection

    var body: some View {
        VStack(spacing: 8) {
            // One picker, exactly the phone's options/order/titles. There is no
            // Strength/Cardio mode switch: scrolling the wheel reaches every
            // workout and Start opens whatever is selected.
            Picker("Workout type", selection: Binding(
                get: { selection.choice },
                set: { selection.select($0) })) {
                ForEach(selection.choices) { option in
                    Label(LocalizedStringKey(option.title), systemImage: option.symbol)
                        .tag(option)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 80)
            .clipped()
            .accessibilityLabel("Workout type")
            .accessibilityValue(Text(LocalizedStringKey(selection.choice.title)))
            .accessibilityIdentifier("watch.workoutPicker")

            WatchPrimaryStartButton(title: "Start Workout") {
                WatchHaptics.tap()
                selection.start()
            }
            .accessibilityHint("Opens the selected workout")
            .accessibilityIdentifier("watch.startWorkout")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .onChange(of: selection.choice) { _, _ in selection.persist() }
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
