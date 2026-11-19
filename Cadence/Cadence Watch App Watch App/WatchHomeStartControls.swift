import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

struct WatchHomeStartControls: View {
    @Binding var selection: WatchHomeWorkoutSelection

    var body: some View {
        // Instant picker: tapping Strength/Cardio (WatchHomeStartNavigation's
        // mode buttons) already shows this list immediately; tapping a row
        // here both selects AND starts it in one step, same as the phone's
        // dropdown Menu -- no separate wheel-scroll + Start tap.
        VStack(alignment: .leading, spacing: 4) {
            ForEach(selection.choices) { option in
                Button {
                    WatchHaptics.tap()
                    selection.selectAndStart(option)
                    selection.persist()
                } label: {
                    Label(LocalizedStringKey(selection.title(for: option)), systemImage: option.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watch.workoutChoice.\(option.id)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .accessibilityLabel(selection.mode == .strength ? "Strength workout" : "Cardio workout")
        .accessibilityIdentifier("watch.workoutPicker")
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
        case .suggestedCardio:
            // Unreachable: "Personalized Cardio" is phone-only — excluded from
            // `WatchHomeWorkoutSelection.choices` so it never appears in the
            // Watch wheel/list in the first place.
            EmptyView()
        }
    }
}
