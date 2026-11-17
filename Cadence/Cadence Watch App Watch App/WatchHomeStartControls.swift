import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

struct WatchHomeStartControls: View {
    @Binding var selection: WatchHomeWorkoutSelection

    var body: some View {
        VStack(spacing: 8) {
            Picker("Workout type", selection: Binding(
                get: { selection.selection }, set: { selection.select($0) })) {
                ForEach(selection.choices) { option in
                    Label(LocalizedStringKey(selection.title(for: option)), systemImage: option.symbol)
                        .tag(option)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 44)
            .clipped()
            .accessibilityLabel(selection.mode == .strength ? "Strength workout" : "Cardio workout")
            .accessibilityIdentifier("watch.workoutPicker")

            WatchPrimaryStartButton { selection.start() }
            .accessibilityHint("Opens the selected workout")
            .accessibilityIdentifier("watch.startWorkout")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .onChange(of: selection.strengthChoice) { _, _ in selection.persist() }
        .onChange(of: selection.cardioChoice) { _, _ in selection.persist() }
    }
}

/// Attach outside the List's lazy rows so navigation destinations are always
/// registered, and the home toolbar stays anchored to the screen corners.
struct WatchHomeStartNavigation: ViewModifier {
    @Binding var selection: WatchHomeWorkoutSelection
    let showsModeButtons: Bool
    let cardioDestination: (CardioType) -> AnyView

    func body(content: Content) -> some View {
        content
        .toolbar {
            if showsModeButtons {
                ToolbarItemGroup(placement: .bottomBar) {
                    modeButton(.strength, symbol: "dumbbell.fill", title: "Strength workouts")
                    Spacer()
                    modeButton(.cardio, symbol: "figure.mixed.cardio", title: "Cardio workouts")
                }
            }
        }
        .navigationDestination(item: Binding(
            get: { selection.launchChoice },
            set: { if $0 == nil { selection.dismissStart() } })) { choice in
                destination(for: choice)
            }
    }

    private func modeButton(_ mode: WatchHomeWorkoutSelection.Mode, symbol: String, title: String) -> some View {
        Button { selection.show(mode) } label: {
            Image(systemName: symbol)
        }
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selection.mode == mode ? .isSelected : [])
        .accessibilityIdentifier(mode == .strength ? "watch.mode.strength" : "watch.mode.cardio")
    }

    @ViewBuilder
    private func destination(for choice: HomeWorkoutStartChoice) -> some View {
        switch choice {
        case .strength(.quickStart):
            WatchStrengthPreview(launch: WatchLiftLaunch(title: "Custom Strength", exerciseNames: [], repLadder: []))
        case .strength(.suggested): WatchHomeSuggestedStrengthView()
        case .strength(.previous): WatchPreviousListView()
        case .cardio(let type):
            if let cardio = type.cardioType { cardioDestination(cardio) }
        }
    }
}
