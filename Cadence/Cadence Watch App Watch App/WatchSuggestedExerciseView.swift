import SwiftUI
import CadenceCore
import CadenceFeatures

/// Watch "Suggest exercise". The workout changes only when the user confirms
/// Add in the native dialog; Details, Suggest another and Cancel never add.
struct WatchSuggestedExerciseView: View {
    let model: WatchStrengthFlowModel
    let catalog: ExerciseCatalogSnapshot
    let onRefreshCatalog: () -> Void
    let onBack: () -> Void
    @State private var shell = WatchSuggestedExerciseShell()
    @State private var confirmation = WatchAddConfirmation()
    @State private var showingDetails = false
    @State private var showingDetail = false

    var body: some View {
        content
            .navigationTitle("")
            .task { shell.start(activeNames: activeNames, activeWorkingSets: activeSets) }
            .modifier(WatchAddConfirmationModifier(
                confirmation: $confirmation,
                onAdd: performConfirmedAdd,
                onViewWorkout: { model.goBackToHome() },
                onRefresh: {
                    confirmation.dismissOutcome()
                    onRefreshCatalog()
                }))
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
            readyCard(exercise)
        }
    }

    @ViewBuilder private func readyCard(_ exercise: SuggestedWorkoutExercise) -> some View {
        let entry = WatchSuggestedExerciseCard.resolve(exercise, in: catalog)
        if showingDetails, let entry {
            WatchAddExercisePreview(entry: entry, feedback: nil, showingDetail: $showingDetail,
                                    onBack: { showingDetails = false },
                                    onAdd: { requestAdd(exercise, entry) })
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    Text(exercise.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("watchSuggest.name")
                    Text(WatchSuggestedExerciseCard.prescriptionText(exercise))
                        .font(.footnote)
                        .accessibilityIdentifier("watchSuggest.prescription")
                    let chips = WatchSuggestedExerciseCard.muscleChips(for: exercise, entry: entry)
                    if !chips.isEmpty {
                        Text(chips.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("watchSuggest.why")
                    }
                    if entry == nil {
                        Text(WatchSuggestedExerciseCard.unavailableMessage)
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("watchSuggest.catalogUnavailable")
                        Button {
                            WatchHaptics.tap()
                            onRefreshCatalog()
                        } label: {
                            Text("Refresh").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityIdentifier("watchSuggest.refresh")
                    }
                    Button {
                        if let entry { requestAdd(exercise, entry) }
                    } label: {
                        Label("Add to workout", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(entry == nil)
                    .accessibilityIdentifier("watchSuggest.add")
                    Button {
                        WatchHaptics.tap()
                        shell.suggestAnother(activeNames: activeNames, activeWorkingSets: activeSets)
                    } label: {
                        Text("Suggest another").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("watchSuggest.another")
                    Button {
                        WatchHaptics.tap()
                        showingDetail = false
                        showingDetails = true
                    } label: {
                        Text("Details").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(entry == nil)
                    .accessibilityIdentifier("watchSuggest.details")
                    Button(role: .cancel) {
                        WatchHaptics.tap()
                        onBack()
                    } label: {
                        Text("Cancel").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watchSuggest.cancel")
                }
            }
            .accessibilityIdentifier("watchSuggest.ready")
        }
    }

    private func requestAdd(_ exercise: SuggestedWorkoutExercise, _ entry: ExerciseCatalogEntry) {
        confirmation.request(.init(id: entry.id, name: entry.name))
        WatchHaptics.tap()
    }

    /// Only mutation path; reached from the confirmation dialog's Add.
    private func performConfirmedAdd() {
        guard case .ready(let exercise) = shell.phase else { confirmation.cancel(); return }
        guard let result = confirmation.confirm(add: {
            model.addSuggestedExercise(id: $0, name: $1, sets: exercise.plannedSets,
                                       repRange: exercise.repRange)
        }) else { return }
        let outcome = WatchExerciseAddPresenter.outcome(for: result)
        switch outcome.feedback {
        case .success: WatchHaptics.success()
        case .failure:
            WatchHaptics.failure()
            AccessibilityNotification.Announcement(outcome.message).post()
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
