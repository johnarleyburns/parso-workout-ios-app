import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct WatchAddExerciseView: View {
    let model: WatchStrengthFlowModel
    @Environment(\.modelContext) private var context
    /// One row, used only to notice catalog changes. The screen used to query
    /// all ~900 exercises on the main thread on open and on every save, then
    /// walk them per render for category lists.
    @Query(ExerciseCatalogSnapshot.changeSignalDescriptor) private var newestExercise: [Exercise]
    /// Built on a background context; see `ExerciseCatalogSnapshot`.
    @State private var catalog = ExerciseCatalogSnapshot.empty
    @State private var selectedGroup: MuscleGroup?
    @State private var showingRecent = false
    @State private var filter = WatchExerciseFilter()
    @State private var selectedEntry: ExerciseCatalogEntry?
    @State private var showingDetail = false
    @State private var query = ""
    @State private var searchResults: [ExerciseCatalogEntry] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var showingCustomExercise = false
    @State private var customName = ""
    @State private var customGroups: Set<MuscleGroup> = []
    @State private var showingAllGroups = false
    /// Newest search; older searches may not install results.
    @State private var searchGeneration = 0
    /// Duplicate / failure feedback shown while the user stays in Add Exercise.
    @State private var feedback: String?

    init(model: WatchStrengthFlowModel) {
        self.model = model
    }

    var body: some View {
        Group {
            if showingCustomExercise {
                WatchCustomExerciseForm(name: $customName, groups: $customGroups,
                                        feedback: feedback,
                                        onCreate: { report(model.createAndAddExercise(named: customName, muscleGroups: customGroups)) },
                                        onBack: { showingCustomExercise = false })
            } else if let selectedEntry {
                WatchAddExercisePreview(entry: selectedEntry, feedback: feedback,
                                        showingDetail: $showingDetail,
                                        onBack: { self.selectedEntry = nil },
                                        onAdd: { add(selectedEntry) })
            } else {
                picker
            }
        }
        // No title: it only costs vertical space on the small screen.
        .navigationTitle("")
        .task(id: newestExercise.first?.updatedAt) {
            catalog = await ExerciseCatalogSnapshot.load(from: context.container, recentLimit: 12)
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scheduleSearch(immediate: true)
            }
        }
        .onChange(of: query) { _, _ in
            scheduleSearch()
        }
        .onDisappear {
            searchTask?.cancel()
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
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    Button {
                        WatchHaptics.tap()
                        query = ""
                    } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
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
                Section {
                    customExerciseButton
                }
            } else if let selectedGroup {
                Section {
                    Button {
                        WatchHaptics.tap()
                        self.selectedGroup = nil
                        filter = WatchExerciseFilter()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                }
                if catalog.isLoaded {
                    let groupEntries = catalog.entries(in: selectedGroup)
                    WatchExerciseFilterSection(filter: $filter, entries: groupEntries)
                    let shown = filter.apply(to: groupEntries)
                    Section(selectedGroup.displayName) {
                        if shown.isEmpty {
                            Text("No matches").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(shown) { exercise in
                            exerciseButton(exercise)
                        }
                    }
                } else {
                    Section(selectedGroup.displayName) {
                        loadingRow
                    }
                }
            } else if showingRecent {
                Section {
                    Button {
                        WatchHaptics.tap()
                        showingRecent = false
                    } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
                }
                Section("My Last Exercises") {
                    ForEach(catalog.recent) { exercise in
                        exerciseButton(exercise)
                    }
                }
            } else {
                Section {
                    HStack(spacing: 6) {
                        TextField("Search", text: $query)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("watchAddExercise.search")
                        customExerciseButton
                    }
                    if !catalog.recent.isEmpty {
                        Button {
                            WatchHaptics.tap()
                            showingRecent = true
                        } label: { Label("My Last Exercises", systemImage: "clock.arrow.circlepath") }
                        .buttonStyle(.plain)
                    }
                }
                Section("Categories") {
                    ForEach(watchCategoryOrder) { group in
                        Button {
                            WatchHaptics.tap()
                            selectedGroup = group
                        } label: {
                            Text(group.displayName)
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("watchAddExercise.category.\(group.rawValue)")
                    }
                    if !showingAllGroups {
                        Button {
                            WatchHaptics.tap()
                            showingAllGroups = true
                        } label: { Label("More muscles", systemImage: "ellipsis.circle") }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("watchAddExercise.moreCategories")
                    }
                }
            }
        }
        .id(pickerBranchIdentity)
    }

    private var pickerBranchIdentity: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "search" }
        if let selectedGroup { return "group.\(selectedGroup.rawValue)" }
        if showingRecent { return "recent" }
        return "categories"
    }

    private var loadingRow: some View {
        HStack {
            ProgressView()
                .controlSize(.mini)
            Text("Loading exercises")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watchAddExercise.loading")
    }

    private var watchCategoryOrder: [MuscleGroup] {
        let groups = showingAllGroups
            ? MuscleGroup.canonicalOrder
            : MuscleGroup.canonicalOrder.filter(\.isTrackedByDefault)
        return [.chest] + groups.filter { $0 != .chest }
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

    /// The row is a primary "add" action; Details is a separate target. Rows
    /// are plain values, so the stored exercise is only read when added.
    private func exerciseButton(_ exercise: ExerciseCatalogEntry) -> some View {
        HStack(spacing: 6) {
            Button {
                add(exercise)
            } label: {
                Label(exercise.name, systemImage: "plus.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(exercise.name)")
            .accessibilityIdentifier("watchAddExercise.add.\(exercise.id.uuidString)")

            Button {
                WatchHaptics.tap()
                feedback = nil
                selectedEntry = exercise
            } label: {
                Image(systemName: "info.circle")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details for \(exercise.name)")
            .accessibilityIdentifier("watchAddExercise.details.\(exercise.id.uuidString)")
        }
    }

    private func add(_ entry: ExerciseCatalogEntry) {
        report(model.addExercise(id: entry.id, named: entry.name))
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
