import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Search-first Add Exercise flow shared by the live workout plan page and the
/// pre-workout Lift preview. The caller decides how an added exercise is stored;
/// this view only owns search, the local suggestion, and feedback.
struct WatchAddExercisePicker: View {
    let existingNames: [String]
    let activeWorkingSets: [WatchSuggestionSet]
    let onAddCatalog: (ExerciseCatalogEntry) -> WatchExerciseAddResult
    let onAddSuggested: (SuggestedWorkoutExercise, ExerciseCatalogEntry) -> WatchExerciseAddResult
    let onCreateCustom: (String, WatchCustomExerciseMuscleAttribution) -> WatchExerciseAddResult
    let onBack: () -> Void
    let onAdded: () -> Void

    @Environment(\.modelContext) private var context
    /// One row, used only to notice catalog changes.
    @Query(ExerciseCatalogSnapshot.changeSignalDescriptor) private var newestExercise: [Exercise]
    @State private var catalog = ExerciseCatalogSnapshot.empty
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    @State private var searchResults: [WatchAddExerciseSearchRow] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var showingCustomExercise = false
    @State private var customName = ""
    @State private var customAttribution = WatchCustomExerciseMuscleAttribution()
    @State private var searchGeneration = 0
    @State private var feedback: String?
    @State private var suggestionShell = WatchSuggestedExerciseShell()
    @State private var suggestedExercise: SuggestedWorkoutExercise?
    @State private var suggestedEntry: ExerciseCatalogEntry?

    var body: some View {
        Group {
            if showingCustomExercise {
                WatchCustomExerciseForm(
                    name: $customName,
                    attribution: $customAttribution,
                    feedback: feedback,
                    onCreate: { report(onCreateCustom(customName, customAttribution)) },
                    onBack: { showingCustomExercise = false })
            } else {
                picker
            }
        }
        .navigationTitle(LocalizedStringKey(WatchAddExerciseSuggestionPresentation.pageTitle))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                WatchBackButton { onBack() }
            }
        }
        .task {
            suggestionShell.start(activeNames: existingNames,
                                  activeWorkingSets: activeWorkingSets)
        }
        .onChange(of: suggestionShell.session.state, initial: true) { _, _ in
            updateSuggestion(suggestionShell.phase)
        }
        .onChange(of: catalog.isLoaded) { _, _ in
            updateSuggestion(suggestionShell.phase)
        }
        .onChange(of: existingNames) { _, _ in
            updateSuggestion(suggestionShell.phase)
        }
        .task(id: newestExercise.first?.updatedAt) {
            catalog = await ExerciseCatalogSnapshot.load(from: context.container, recentLimit: 0)
            if !queryTrimmed.isEmpty {
                scheduleSearch(immediate: true)
            }
        }
        .onChange(of: query) { _, _ in
            scheduleSearch()
        }
        .onAppear {
            // Focus is one tap away; watchOS still requires the user's own tap
            // to present the keyboard/dictation sheet.
            isSearchFocused = true
        }
        .onDisappear {
            searchTask?.cancel()
            suggestionShell.cancel()
        }
    }

    private var picker: some View {
        List {
            if let feedback {
                Text(feedback)
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("watchAddExercise.feedback")
            }
            TextField("Search", text: $query)
                .focused($isSearchFocused)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("watchAddExercise.search")

            if queryIsEmpty {
                suggestedExerciseSection
            } else {
                Section("Matches") {
                    searchPhaseContent
                }
            }
            // Add Custom is always the last row, after the suggestions or the
            // matches, so it never pushes the exercise list down from the top.
            addCustomRow
        }
    }

    @ViewBuilder
    private var suggestedExerciseSection: some View {
        if let exercise = suggestedExercise, let entry = suggestedEntry {
            Section {
                Button {
                    WatchHaptics.tap()
                    report(onAddSuggested(exercise, entry))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name.localizedExerciseName)
                            .font(.body)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(WatchSuggestedExerciseCard.prescriptionText(exercise))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(exercise.name.localizedExerciseName))
                .accessibilityHint(Text(LocalizedStringKey(WatchAddExerciseSuggestionPresentation.rowAccessibilityHint)))
                .accessibilityIdentifier(
                    WatchAddExerciseSuggestionPresentation.rowIdentifierPrefix + exercise.candidateID)
            } header: {
                Text(LocalizedStringKey(WatchAddExerciseSuggestionPresentation.sectionTitle))
            }
        }
    }

    private var addCustomRow: some View {
        Button {
            WatchHaptics.tap()
            customName = queryTrimmed
            showingCustomExercise = true
        } label: {
            Label(LocalizedStringKey(WatchAddExerciseSuggestionPresentation.customRowTitle),
                  systemImage: "plus.circle")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watchAddExercise.custom")
    }

    @ViewBuilder
    private var searchPhaseContent: some View {
        switch WatchExerciseSearchPresenter.phase(query: query,
                                                  isSearching: isSearching,
                                                  resultCount: searchResults.count) {
        case .searching:
            HStack {
                ProgressView().controlSize(.mini)
                Text("Searching")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("watchAddExercise.searching")
        case .noMatches:
            Text("No matches")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("watchAddExercise.noMatches")
        case .matches:
            ForEach(searchResults) { row in
                exerciseButton(row)
            }
        case .empty:
            EmptyView()
        }
    }

    private func exerciseButton(_ row: WatchAddExerciseSearchRow) -> some View {
        Button {
            WatchHaptics.tap()
            report(onAddCatalog(ExerciseCatalogEntry(id: row.id, name: row.name)))
        } label: {
            Text(row.displayName)
                .lineLimit(WatchAddExercisePresentation.exerciseNameMaxLines, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity,
                       minHeight: WatchAddExercisePresentation.minimumTouchHeight,
                       alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WatchAddExercisePresentation.rowAccessibilityLabel(for: row.name))
        .accessibilityHint(WatchAddExercisePresentation.rowAccessibilityHint)
        .accessibilityIdentifier("watchAddExercise.row.\(row.id.uuidString)")
    }

    private func updateSuggestion(_ phase: WatchSuggestedExerciseShell.Phase) {
        guard case .ready(let exercise) = phase,
              !WatchExerciseSuggestionGuard.isAlreadyInWorkout(exercise.name, activeNames: existingNames),
              let entry = WatchSuggestedExerciseCard.resolve(exercise, in: catalog) else {
            suggestedExercise = nil
            suggestedEntry = nil
            return
        }
        suggestedExercise = exercise
        suggestedEntry = entry
    }

    private func report(_ result: WatchExerciseAddResult) {
        let outcome = WatchExerciseAddPresenter.outcome(for: result)
        switch outcome.feedback {
        case .success: WatchHaptics.success()
        case .failure: WatchHaptics.failure()
        }
        if outcome.returnsToPlan {
            feedback = nil
            onAdded()
        } else {
            feedback = outcome.message
            AccessibilityNotification.Announcement(outcome.message).post()
        }
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        let trimmed = queryTrimmed
        guard !trimmed.isEmpty else {
            isSearching = false
            searchResults = []
            return
        }

        isSearching = true
        searchResults = []
        guard catalog.isLoaded else { return }
        let snapshot = catalog
        searchTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled else { return }
            let matches = await Task.detached(priority: .userInitiated) {
                snapshot.search(trimmed, limit: WatchExerciseSearchPresenter.resultLimit).map {
                    WatchAddExerciseSearchRow(id: $0.id, name: $0.name,
                                              displayName: $0.name.localizedExerciseName)
                }
            }.value
            guard !Task.isCancelled,
                  WatchExerciseAddPresenter.acceptsSearchResults(
                    generation: generation, current: searchGeneration,
                    searchedQuery: trimmed, currentQuery: query) else { return }
            searchResults = matches
            isSearching = false
        }
    }

    private var queryTrimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var queryIsEmpty: Bool { queryTrimmed.isEmpty }
}

struct WatchAddExerciseSearchRow: Identifiable, Sendable {
    let id: UUID
    let name: String
    let displayName: String
}
