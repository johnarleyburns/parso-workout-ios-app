import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

struct WatchAddExerciseView: View {
    let model: WatchStrengthFlowModel
    @Environment(\.modelContext) private var context
    /// One row, used only to notice catalog changes. The screen used to query
    /// all ~900 exercises on the main thread on open and on every save, then
    /// walk them per render for category lists.
    @Query(ExerciseCatalogSnapshot.changeSignalDescriptor) private var newestExercise: [Exercise]
    /// Built on a background context; see `ExerciseCatalogSnapshot`.
    @State private var catalog = ExerciseCatalogSnapshot.empty
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    @State private var searchResults: [ExerciseCatalogEntry] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var showingCustomExercise = false
    @State private var customName = ""
    @State private var customAttribution = WatchCustomExerciseMuscleAttribution()
    /// Newest search; older searches may not install results.
    @State private var searchGeneration = 0
    /// Duplicate / failure feedback shown while the user stays in Add Exercise.
    @State private var feedback: String?
    /// One personalized suggestion, calculated locally from the phone mirror.
    @State private var suggestionShell = WatchSuggestedExerciseShell()

    init(model: WatchStrengthFlowModel) {
        self.model = model
    }

    var body: some View {
        Group {
            if showingCustomExercise {
                WatchCustomExerciseForm(name: $customName, attribution: $customAttribution,
                                        feedback: feedback,
                                        onCreate: { report(model.createAndAddExercise(named: customName, attribution: customAttribution)) },
                                        onBack: { showingCustomExercise = false })
            } else {
                picker
            }
        }
        // The screen still has one compact title/back row; the navigation bar
        // itself stays out of the way on the small screen.
        .navigationTitle("")
        .task {
            suggestionShell.start(activeNames: model.suggestionActiveExerciseNames,
                                  activeWorkingSets: model.suggestionActiveWorkingSets)
        }
        .task(id: newestExercise.first?.updatedAt) {
            catalog = await ExerciseCatalogSnapshot.load(from: context.container, recentLimit: 0)
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scheduleSearch(immediate: true)
            }
        }
        .onChange(of: query) { _, _ in
            scheduleSearch()
        }
        .onAppear {
            // Search-first entry (field-testing batch): raise focus immediately
            // so the system keyboard/dictation affordance is one tap away
            // instead of landing on a category-browse screen first. watchOS
            // still requires the user's own tap to actually present the
            // keyboard sheet — focus alone can't force it open.
            isSearchFocused = true
        }
        .onDisappear {
            searchTask?.cancel()
            suggestionShell.cancel()
        }
    }

    private var picker: some View {
        List {
            HStack(spacing: 4) {
                WatchBackButton {
                    WatchHaptics.tap()
                    model.goBackToHome()
                }
                Text(LocalizedStringKey(WatchAddExerciseSuggestionPresentation.pageTitle))
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("watchAddExercise.title")
            }
            if let feedback {
                Text(feedback)
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("watchAddExercise.feedback")
            }
            HStack(spacing: 6) {
                TextField("Search", text: $query)
                    .focused($isSearchFocused)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("watchAddExercise.search")
                customExerciseButton
            }
            suggestedExerciseSection
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    Button {
                        WatchHaptics.tap()
                        model.goBackToHome()
                    } label: { Label("Cancel", systemImage: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watchAddExercise.cancel")
                }
                Section("Matches") {
                    switch WatchExerciseSearchPresenter.phase(query: query,
                                                              isSearching: isSearching,
                                                              resultCount: searchResults.count) {
                    case .searching:
                        HStack {
                            ProgressView()
                                .controlSize(.mini)
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
                        ForEach(searchResults) { exercise in
                            exerciseButton(exercise)
                        }
                    case .empty:
                        EmptyView()
                    }
                }
            }
        }
        .id(pickerBranchIdentity)
    }

    @ViewBuilder
    private var suggestedExerciseSection: some View {
        if case .ready(let exercise) = suggestionShell.phase,
           !WatchExerciseSuggestionGuard.isAlreadyInWorkout(
                exercise.name, activeNames: model.suggestionActiveExerciseNames),
           let entry = WatchSuggestedExerciseCard.resolve(exercise, in: catalog) {
            Section {
                Button {
                    WatchHaptics.tap()
                    report(model.addSuggestedExercise(id: entry.id, name: entry.name,
                                                      sets: exercise.plannedSets,
                                                      repRange: exercise.repRange))
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

    private var pickerBranchIdentity: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "idle" : "search"
    }

    private var customExerciseButton: some View {
        Button {
            WatchHaptics.tap()
            customName = query.trimmingCharacters(in: .whitespacesAndNewlines)
            showingCustomExercise = true
        } label: {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "plus.circle")
            } else {
                Label(customNameLabel, systemImage: "plus.circle")
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(customNameLabel)
        .accessibilityIdentifier("watchAddExercise.custom")
    }

    private var customNameLabel: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Add Custom Exercise") : String(localized: "Add Custom “\(trimmed)”")
    }

    /// Tapping a result adds it immediately — no preview screen, no confirm
    /// dialog (field-testing batch: "I can always easily remove an added
    /// exercise", so a confirm step here is friction, not safety).
    private func exerciseButton(_ exercise: ExerciseCatalogEntry) -> some View {
        Button {
            WatchHaptics.tap()
            report(model.addExercise(id: exercise.id, named: exercise.name))
        } label: {
            Text(WatchAddExercisePresentation.rowTitle(for: exercise.name.localizedExerciseName))
                .lineLimit(WatchAddExercisePresentation.exerciseNameMaxLines, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity,
                       minHeight: WatchAddExercisePresentation.minimumTouchHeight,
                       alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WatchAddExercisePresentation.rowAccessibilityLabel(for: exercise.name))
        .accessibilityHint(WatchAddExercisePresentation.rowAccessibilityHint)
        .accessibilityIdentifier("watchAddExercise.row.\(exercise.id.uuidString)")
    }

    /// Success hands off to the Plan page (the model's stage change), which
    /// shows the confirmation; everything else keeps the picker, query and
    /// results in place with a visible message.
    private func report(_ result: WatchExerciseAddResult) {
        let outcome = WatchExerciseAddPresenter.outcome(for: result)
        switch outcome.feedback {
        case .success: WatchHaptics.success()
        case .failure: WatchHaptics.failure()
        }
        if outcome.returnsToPlan {
            feedback = nil
        } else {
            feedback = outcome.message
            AccessibilityNotification.Announcement(outcome.message).post()
        }
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSearching = false
            searchResults = []
            return
        }

        isSearching = true
        searchResults = []
        // Stays "Searching" until the catalog has loaded; the load reruns this.
        guard catalog.isLoaded else { return }
        let snapshot = catalog
        searchTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled else { return }
            let matches = await Task.detached(priority: .userInitiated) {
                snapshot.search(trimmed, limit: WatchExerciseSearchPresenter.resultLimit)
            }.value
            guard !Task.isCancelled,
                  WatchExerciseAddPresenter.acceptsSearchResults(
                    generation: generation, current: searchGeneration,
                    searchedQuery: trimmed, currentQuery: query) else { return }
            searchResults = matches
            isSearching = false
        }
    }
}
