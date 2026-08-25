import SwiftUI
import SwiftData
import CadenceCore

struct ExercisePickerView: View {
    enum PickAction {
        case add, swap, use

        var navigationTitle: String {
            switch self {
            case .add: return "Add Exercise"
            case .swap: return "Swap Exercise"
            case .use: return "Choose Exercise"
            }
        }

        var detailActionTitle: String {
            switch self {
            case .add: return "Add"
            case .swap: return "Swap"
            case .use: return "Use Exercise"
            }
        }
    }

    enum PickerTab: String, CaseIterable { case recents, popular, browse }

    enum BrowseMode: String, CaseIterable { case byMuscleGroup, byEquipment }

    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Environment(AppModel.self) var appModel
    @Query(sort: \Exercise.name) var exercises: [Exercise]
    @State var query = ""
    /// The snapshot of everything a query implies — results, exact-match flag and
    /// the "good match" suggestion — recomputed only when the debounced query
    /// changes, never on a redraw (field test 2026-08-19 #4).
    @State var search = ExercisePickerSearch()
    @State var outcome = ExercisePickerSearch.Outcome.empty
    @State var facetIndex = ExerciseFacetIndex<Exercise>([])
    @State var selectedTab: PickerTab = .recents
    @State var selectedGroup: MuscleGroup?
    @State var selectedEquipment: Equipment?
    @State var browseMode: BrowseMode = .byMuscleGroup
    @State var browseAll = false
    @State var recents: [Exercise] = []
    @State var showCreationSheet = false
    @State var selectedCreationCategory: ExerciseCategory = .other
    @State var selectedCreationMuscles: Set<String> = []
    @State var selectedCreationSecondary: Set<String> = []
    let action: PickAction
    let onPick: (Exercise) -> Void

    init(action: PickAction = .add, onPick: @escaping (Exercise) -> Void) {
        self.action = action
        self.onPick = onPick
    }

    var trimmedQuery: String { outcome.query }

    var popular: [Exercise] { search.popular }

    var filtered: [Exercise] {
        if !trimmedQuery.isEmpty { return outcome.results }
        switch selectedTab {
        case .recents: return recents
        case .popular: return browseAll ? exercises : popular
        case .browse:
            switch browseMode {
            case .byMuscleGroup:
                if let group = selectedGroup { return facetIndex.exercises(for: group, equipment: selectedEquipment) }
                return exercises
            case .byEquipment:
                if let eq = selectedEquipment { return facetIndex.exercises(forEquipment: eq, group: selectedGroup) }
                return exercises
            }
        }
    }

    var availableEquipment: [Equipment] {
        switch browseMode {
        case .byMuscleGroup:
            guard let group = selectedGroup else { return [] }
            return facetIndex.equipment(for: group)
        case .byEquipment:
            return Equipment.allCases.filter { !facetIndex.exercises(forEquipment: $0).isEmpty }
        }
    }

    /// The groups offered in the browse chip row. Tracked groups lead (they are
    /// what most people browse for); the rest follow in canonical order rather than
    /// being hidden, since browsing is discovery, not programming.
    var availableGroups: [MuscleGroup] {
        switch browseMode {
        case .byMuscleGroup:
            return MuscleGroup.canonicalOrder.filter { !facetIndex.exercises(for: $0).isEmpty }
        case .byEquipment:
            guard let eq = selectedEquipment else { return [] }
            return facetIndex.muscleGroups(forEquipment: eq)
        }
    }

    func rebuildIndexIfNeeded() {
        guard search.rebuildIfNeeded(exercises) else { return }
        facetIndex = ExerciseFacetIndex(exercises)
        if !query.isEmpty { outcome = search.outcome(for: query) }
    }

    var grouped: [(ExerciseCategory, [Exercise])] {
        let dict = Dictionary(grouping: filtered) { $0.categoryValue ?? .other }
        return ExerciseCategory.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items.sorted { $0.name < $1.name })
        }
    }

    var exactMatchExists: Bool { outcome.exactMatch }

    var bestLibraryMatch: Exercise? { outcome.bestMatch }

    var showsGrouped: Bool {
        selectedTab == .browse && trimmedQuery.isEmpty && selectedGroup == nil && selectedEquipment == nil
    }

    var showsFilterChips: Bool {
        selectedTab == .browse && trimmedQuery.isEmpty
    }

    var showsSubFilter: Bool {
        showsFilterChips && browseMode == .byMuscleGroup
            && selectedGroup != nil && availableEquipment.count > 1
    }

    var showsSubFilterInverted: Bool {
        showsFilterChips && browseMode == .byEquipment
            && selectedEquipment != nil && availableGroups.count > 0
    }

    var sectionTitle: String {
        if !trimmedQuery.isEmpty { return "Results" }
        switch selectedTab {
        case .recents: return "Recent"
        case .popular: return browseAll ? "All" : "Popular"
        case .browse:
            switch browseMode {
            case .byMuscleGroup:
                if let group = selectedGroup {
                    if let eq = selectedEquipment { return "\(group.displayName)  \(eq.displayName)" }
                    return group.displayName
                }
                return "All"
            case .byEquipment:
                if let eq = selectedEquipment {
                    if let group = selectedGroup { return "\(eq.displayName)  \(group.displayName)" }
                    return eq.displayName
                }
                return "All"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    Text("Recents").tag(PickerTab.recents)
                    Text("Popular").tag(PickerTab.popular)
                    Text("Browse").tag(PickerTab.browse)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                List {
                    if showsFilterChips {
                        browseModePicker
                        filterChips
                        if showsSubFilter { equipmentChips }
                        if showsSubFilterInverted { muscleGroupSubChips }
                    }

                    if !trimmedQuery.isEmpty && !exactMatchExists {
                        Section {
                            Button { showCreationSheet = true } label: {
                                Label("Create \(query)", systemImage: "plus.circle.fill")
                            }
                            .accessibilityIdentifier("picker.create")
                        }
                    }

                    if !trimmedQuery.isEmpty, let match = bestLibraryMatch {
                        Section {
                            HStack {
                                Image(systemName: "sparkle.magnifyingglass")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading) {
                                    Text("Found a good match")
                                        .font(.subheadline.weight(.medium))
                                    Text(match.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Use this exercise") {
                                    onPick(match)
                                    dismiss()
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }

                    if selectedTab == .recents, trimmedQuery.isEmpty, recents.isEmpty {
                        Section {
                            ContentUnavailableView("No recent exercises",
                                                   systemImage: "clock.arrow.circlepath",
                                                   description: Text("Log a workout to see exercises here."))
                        }
                    } else if showsGrouped {
                        ForEach(grouped, id: \.0) { cat, items in
                            Section(cat.displayName) { ForEach(items) { exerciseRow($0) } }
                        }
                    } else {
                        Section(sectionTitle) { ForEach(filtered) { exerciseRow($0) } }
                        if selectedTab == .popular, !browseAll, trimmedQuery.isEmpty {
                            Section {
                                Button { browseAll = true } label: {
                                    Label("Browse all exercises", systemImage: "square.grid.2x2")
                                }
                                .accessibilityIdentifier("picker.browseAll")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(action.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .searchable(text: $query, prompt: "Search name, muscle, or equipment")
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailView(exercise: exercise, actionTitle: action.detailActionTitle) { picked in
                    onPick(picked)
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("picker.cancel")
                }
            }
        }
        .accessibilityIdentifier("picker.search")
        .onAppear {
            rebuildIndexIfNeeded()
            loadRecents()
            if recents.isEmpty { selectedTab = .popular }
        }
        .onChange(of: exercises.count) { _, _ in rebuildIndexIfNeeded() }
        .onChange(of: selectedGroup) { _, _ in selectedEquipment = nil }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .browse { selectedEquipment = nil; selectedGroup = nil }
            if newTab != .browse { selectedGroup = nil; selectedEquipment = nil }
            if newTab == .recents { loadRecents() }
        }
        .onChange(of: browseMode) { _, _ in selectedEquipment = nil; selectedGroup = nil }
        .task(id: query) {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                outcome = .empty
                return
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            outcome = search.outcome(for: query)
        }
        .sheet(isPresented: $showCreationSheet) { creationSheet }
    }

    // MARK: Browse mode picker

}
