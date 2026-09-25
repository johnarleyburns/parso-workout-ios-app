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
    @State private var selectedExercise: Exercise?
    @State private var showingDetail = false
    @State private var query = ""
    @State private var searchResults: [ExerciseCatalogEntry] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var showingCustomExercise = false
    @State private var customName = ""
    @State private var customGroups: Set<MuscleGroup> = []
    @State private var showingAllGroups = false

    init(model: WatchStrengthFlowModel) {
        self.model = model
    }

    var body: some View {
        Group {
            if showingCustomExercise {
                customExerciseForm
            } else if let selectedExercise {
                preview(selectedExercise)
            } else {
                picker
            }
        }
        .navigationTitle(showingCustomExercise ? "Custom Exercise" : selectedExercise?.name ?? selectedGroup?.displayName ?? "Add Exercise")
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
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                }
                Section(selectedGroup.displayName) {
                    if catalog.isLoaded {
                        ForEach(catalog.entries(in: selectedGroup)) { exercise in
                            exerciseButton(exercise)
                        }
                    } else {
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
                        } label: { Text(group.displayName) }
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
        .accessibilityLabel(customNameLabel)
        .accessibilityIdentifier("watchAddExercise.custom")
    }

    private var customNameLabel: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Add Custom Exercise" : "Add Custom “\(trimmed)”"
    }

    private var customExerciseForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Exercise name", text: $customName)
                    .accessibilityIdentifier("watchCustom.name")

                Text("Muscle groups")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(MuscleGroup.canonicalOrder) { group in
                        Button {
                            WatchHaptics.tap()
                            if customGroups.contains(group) {
                                customGroups.remove(group)
                            } else {
                                customGroups.insert(group)
                            }
                        } label: {
                            Text(group.displayName)
                                .font(.caption2.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(customGroups.contains(group) ? Color.green.opacity(0.35) : Color.white.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(group.displayName) \(customGroups.contains(group) ? "selected" : "not selected")")
                        .accessibilityIdentifier("watchCustom.muscleGroup.\(group.rawValue)")
                    }
                }

                Button {
                    WatchHaptics.success()
                    _ = model.addCustomExercise(named: customName, muscleGroups: customGroups)
                } label: {
                    Label("Create & Add", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || customGroups.isEmpty)
                .accessibilityIdentifier("watchCustom.create")

                Button("Back") {
                    WatchHaptics.tap()
                    showingCustomExercise = false
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("watchCustom.back")
            }
            .padding()
        }
    }

    @ViewBuilder
    private func preview(_ exercise: Exercise) -> some View {
        if showingDetail {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    WatchExerciseDetailContent(exercise: exercise)
                    quickActions(exercise)
                }
                .padding()
            }
        } else {
            VStack(spacing: 10) {
                Text(exercise.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                quickActions(exercise)
                    .padding(.horizontal)
            }
        }
    }

    private func quickActions(_ exercise: Exercise) -> some View {
        VStack(spacing: 8) {
            Button {
                WatchHaptics.tap()
                selectedExercise = nil
                showingDetail = false
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("watchAddExercise.previewBack")

            Button {
                WatchHaptics.success()
                model.addExercise(named: exercise.name)
            } label: {
                Label("Add", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityIdentifier("watchAddExercise.previewAdd")

            Button {
                WatchHaptics.tap()
                showingDetail = true
            } label: {
                Text("Show Detail")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("watchAddExercise.showDetail")
        }
    }

    /// Rows are plain values; the stored exercise is read only when tapped.
    private func exerciseButton(_ exercise: ExerciseCatalogEntry) -> some View {
        Button {
            WatchHaptics.tap()
            selectedExercise = ExerciseCatalogSnapshot.exercise(id: exercise.id, in: context)
        } label: {
            Text(exercise.name)
                .lineLimit(2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watchAddExercise.row.\(exercise.name)")
    }

    private func scheduleSearch(immediate: Bool = false) {
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
                snapshot.search(trimmed, limit: 8)
            }.value
            guard !Task.isCancelled,
                  query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            searchResults = matches
            isSearching = false
        }
    }
}
