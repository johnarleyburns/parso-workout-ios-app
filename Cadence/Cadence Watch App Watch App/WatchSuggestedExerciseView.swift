import SwiftUI
import CadenceCore
import CadenceFeatures

/// Shell for Watch "Suggest exercise". Result-card actions are owned by a later
/// change; this view never adds an exercise or mutates the workout.
struct WatchSuggestedExerciseView: View {
    let model: WatchStrengthFlowModel
    let onBack: () -> Void
    @State private var shell = WatchSuggestedExerciseShell()

    var body: some View {
        content
            .navigationTitle("")
            .task { shell.start(activeNames: activeNames, activeWorkingSets: activeSets) }
            .onDisappear { shell.cancel() }
    }

    @ViewBuilder private var content: some View {
        switch shell.phase {
        case .calculating:
            ProgressView(WatchSuggestedExerciseShell.calculatingTitle)
                .accessibilityIdentifier("watchSuggest.calculating")
        case .unavailable:
            messageView(WatchSuggestedExerciseShell.unavailableMessage, retry: true,
                        id: "watchSuggest.unavailable")
        case .noEligibleResult:
            messageView(WatchSuggestedExerciseShell.noResultMessage, retry: false,
                        id: "watchSuggest.noResult")
        case .ready(let exercise):
            VStack(spacing: 8) {
                Text(exercise.name).font(.headline)
                backButton
            }
            .accessibilityIdentifier("watchSuggest.ready")
        }
    }

    private func messageView(_ text: String, retry: Bool, id: String) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(text)
                    .font(.footnote)
                    .accessibilityIdentifier(id)
                if retry {
                    Button {
                        WatchHaptics.tap()
                        shell.retry(activeNames: activeNames, activeWorkingSets: activeSets)
                    } label: {
                        Text("Retry").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("watchSuggest.retry")
                }
                backButton
            }
        }
    }

    private var backButton: some View {
        Button {
            WatchHaptics.tap()
            onBack()
        } label: {
            Label("Back", systemImage: "chevron.left")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("watchSuggest.back")
    }

    private var activeNames: [String] {
        let session = model.session
        return (session?.plannedExerciseNames ?? []) + (session?.exercisesInOrder.map(\.name) ?? [])
    }

    private var activeSets: [WatchSuggestionSet] {
        (model.session?.orderedSets ?? []).compactMap { set in
            guard let name = set.exercise?.name else { return nil }
            return WatchSuggestionSet(exerciseName: name, isWarmup: set.isWarmup)
        }
    }
}
