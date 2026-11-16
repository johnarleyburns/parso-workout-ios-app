import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchHomeStartControls: View {
    let cardioDestination: (CardioType) -> AnyView
    @AppStorage(HomeWorkoutStartChoice.selectionStorageKey)
    private var selectedChoiceID = HomeWorkoutStartChoice.defaultChoice.id

    private var selection: HomeWorkoutStartChoice {
        get { HomeWorkoutStartChoice.restored(from: selectedChoiceID) }
        nonmutating set { selectedChoiceID = newValue.id }
    }

    var body: some View {
        VStack(spacing: 5) {
            Picker("Workout type", selection: Binding(
                get: { selection }, set: { selection = $0 })) {
                ForEach(HomeWorkoutStartChoice.allChoices) { option in
                    Label(LocalizedStringKey(option.title), systemImage: option.symbol)
                        .tag(option)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 80)
            .accessibilityIdentifier("watch.workoutPicker")

            NavigationLink {
                destination
            } label: {
                Label("Start", systemImage: "activity.exercise")
            }
            .buttonStyle(WatchPillStyle(kind: .primary))
            .accessibilityIdentifier("watch.startWorkout")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var destination: some View {
        switch selection {
        case .strength(.quickStart): WatchStrengthView(title: "Strength")
        case .strength(.suggested): WatchHomeSuggestedStrengthView()
        case .strength(.previous): WatchPreviousListView()
        case .cardio(let type):
            if let cardio = type.cardioType { cardioDestination(cardio) }
        }
    }
}
