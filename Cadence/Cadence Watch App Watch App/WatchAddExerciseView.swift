import SwiftUI
import SwiftData
import ImageIO
import CadenceCore
import CadenceFeatures

struct WatchAddExerciseView: View {
    let model: WatchStrengthFlowModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var recent: [Exercise] = []
    @State private var selectedGroup: MuscleGroup?
    @State private var showingRecent = false
    @State private var selectedExercise: Exercise?
    @State private var showingDetail = false
    @State private var query = ""
    @State private var searchIndex = ExerciseSearchIndex<Exercise>([])
    @State private var searchResults: [Exercise] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var showingCustomExercise = false
    @State private var customName = ""
    @State private var customGroups: Set<MuscleGroup> = []
    @State private var showingAllGroups = false

    init(model: WatchStrengthFlowModel) {
        self.model = model
        _exercises = Query(sort: \Exercise.name)
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
        .task { loadRecent() }
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
                        ForEach(searchResults, id: \.persistentModelID) { exercise in
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
                    ForEach(WatchExerciseSelection.fullList(for: selectedGroup, exercises: exercises), id: \.self) { name in
                        if let exercise = exercise(named: name) {
                            exerciseButton(exercise)
                        }
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
                    ForEach(recent, id: \.persistentModelID) { exercise in
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
                    if !recent.isEmpty {
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
                    detailContent(exercise)
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

    @ViewBuilder
    private func detailContent(_ exercise: Exercise) -> some View {
                let imageURLs = ExerciseLibrary.imageURLs(forImageName: exercise.imageName)
                if !imageURLs.isEmpty {
                    ForEach(imageURLs, id: \.self) { url in
                        exerciseImage(url)
                    }
                }

                if !exercise.instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(exercise.instructions.prefix(4).enumerated()), id: \.offset) { index, step in
                            Text("\(index + 1). \(step)")
                                .font(.caption2)
                        }
                    }
                } else {
                    Text(exercise.displayFacetTags.prefix(3).joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

    private func exerciseButton(_ exercise: Exercise) -> some View {
        Button {
            WatchHaptics.tap()
            selectedExercise = exercise
        } label: {
            Text(exercise.name)
                .lineLimit(2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watchAddExercise.row.\(exercise.name)")
    }

    @ViewBuilder
    private func exerciseImage(_ url: URL) -> some View {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            Image(decorative: image, scale: 1, orientation: .up)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.18))
                .frame(height: 96)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func exercise(named name: String) -> Exercise? {
        exercises.first {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }
    }

    private func loadRecent() {
        recent = (try? WorkoutRepository.recentlyUsedExercises(context, limit: 12)) ?? []
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
        searchTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled else { return }
            if searchIndex.count != exercises.count {
                searchIndex = ExerciseSearchIndex(exercises)
            }
            let matches = Array(searchIndex.rank(trimmed).prefix(8))
            guard query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            searchResults = matches
            isSearching = false
        }
    }
}
