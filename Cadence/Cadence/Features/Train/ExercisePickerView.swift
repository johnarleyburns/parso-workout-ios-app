import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct ExercisePickerView: View {
    enum PickAction: Equatable {
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

    /// NavigationPath stores only this stable value. The SwiftData exercise is
    /// resolved at the destination boundary so a catalog refresh or CloudKit
    /// merge cannot leave a live model embedded in the path.
    enum ExerciseDetailRoute: Hashable {
        case exercise(UUID)
    }

    enum PickerTab: String, CaseIterable { case browse, recents, popular }

    enum BrowseMode: String, CaseIterable { case byMuscleGroup, byEquipment }

    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Environment(AppModel.self) var appModel
    /// One row, used only to notice catalog changes. The picker used to query
    /// and index all ~900 exercises on the main thread as it opened, and
    /// re-walk them on every redraw (once a second during a live workout).
    @Query(ExerciseCatalogSnapshot.changeSignalDescriptor) var newestExercise: [Exercise]
    @State var query = ""
    /// The catalog and its indexes, built on a background context.
    @State var search = ExercisePickerSearch.empty
    /// The snapshot of everything a query implies — results, exact-match flag and
    /// the "good match" suggestion — recomputed only when the debounced query
    /// changes, never on a redraw (field test 2026-08-19 #4).
    @State var outcome = ExercisePickerSearch.Outcome.empty
    @State var selectedTab: PickerTab = .browse
    @State var selectedGroup: MuscleGroup?
    @State var selectedEquipment: Equipment?
    @State var browseMode: BrowseMode = .byMuscleGroup
    @State var browseAll = false
    @State var showCreationSheet = false
    @State var selectedCreationCategory: ExerciseCategory = .other
    @State var selectedCreationMuscles: Set<String> = []
    @State var selectedCreationSecondary: Set<String> = []
    let action: PickAction
    let source: Exercise?
    let onPick: (Exercise) -> Void

    init(action: PickAction = .add, source: Exercise? = nil, onPick: @escaping (Exercise) -> Void) {
        self.action = action
        self.source = source
        self.onPick = onPick
    }

    var trimmedQuery: String { outcome.query }

    var catalog: ExerciseCatalogSnapshot { search.catalog }
    var facetIndex: ExerciseFacetIndex<ExerciseCatalogEntry> { catalog.facets }

    var searchedPrimaryGroup: MuscleGroup? {
        ExerciseSearch.primaryMuscleGroup(matching: trimmedQuery)
    }

    var popular: [ExerciseCatalogEntry] { search.popular }

    var filtered: [ExerciseCatalogEntry] {
        if !trimmedQuery.isEmpty { return outcome.results }
        switch selectedTab {
        case .recents: return catalog.recent
        case .popular: return browseAll ? catalog.entries : popular
        case .browse:
            switch browseMode {
            case .byMuscleGroup:
                if let group = selectedGroup { return facetIndex.exercises(for: group, equipment: selectedEquipment) }
                return catalog.entries
            case .byEquipment:
                if let eq = selectedEquipment { return facetIndex.exercises(forEquipment: eq, group: selectedGroup) }
                return catalog.entries
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

    func primaryFocusLabel(_ ex: ExerciseCatalogEntry) -> String? {
        let group = searchedPrimaryGroup ?? ex.primaryMuscleGroups.first
        guard let group else { return nil }
        let percent = ExerciseSearch.primaryFocusPercent(primaryMuscles: ex.primaryMuscleGroups,
                                                         group: group)
        guard percent > 0 else { return nil }
        return group.displayName + " primary focus " + String(percent) + "%"
    }

    var exactMatchExists: Bool { outcome.exactMatch }

    var bestLibraryMatch: ExerciseCatalogEntry? { outcome.bestMatch }

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

    @ViewBuilder
    var body: some View {
        if action == .swap, let source {
            ExerciseSwapView(source: source, onPick: onPick)
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    Text("Browse").tag(PickerTab.browse)
                    Text("Recents").tag(PickerTab.recents)
                    Text("Popular").tag(PickerTab.popular)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                List {
                    if !catalog.isLoaded {
                        Section {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Loading exercises…").foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("picker.loading")
                        }
                    }
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
                                Button("Use this exercise") { pick(match) }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }

                    if selectedTab == .recents, trimmedQuery.isEmpty, catalog.isLoaded, catalog.recent.isEmpty {
                        Section {
                            ContentUnavailableView("No recent exercises",
                                                   systemImage: "clock.arrow.circlepath",
                                                   description: Text("Log a workout to see exercises here."))
                        }
                    } else if showsGrouped {
                        // Precomputed with the catalog; it used to be regrouped
                        // and re-sorted on every redraw.
                        ForEach(catalog.categorySections) { section in
                            Section(section.category.displayName) { ForEach(section.entries) { exerciseRow($0) } }
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
            .navigationDestination(for: ExerciseDetailRoute.self) { route in
                switch route {
                case .exercise(let id):
                    if let exercise = ExerciseCatalogSnapshot.exercise(id: id, in: context) {
                        ExerciseDetailView(exercise: exercise, actionTitle: action.detailActionTitle) { picked in
                            onPick(picked)
                            dismiss()
                        }
                    } else {
                        ContentUnavailableView(
                            "Exercise unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text("This exercise is no longer available in the local catalog. Return and try again."))
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("picker.cancel")
                }
            }
        }
        .accessibilityIdentifier("picker.search")
        .task(id: newestExercise.first?.updatedAt) {
            search = await ExercisePickerSearch.load(from: context.container)
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                outcome = search.outcome(for: query)
            }
        }
        .onChange(of: selectedGroup) { _, _ in selectedEquipment = nil }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .browse { selectedEquipment = nil; selectedGroup = nil }
            if newTab != .browse { selectedGroup = nil; selectedEquipment = nil }
        }
        .onChange(of: browseMode) { _, _ in selectedEquipment = nil; selectedGroup = nil }
        .task(id: query) {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                outcome = .empty
                return
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            // Before the catalog loads there is nothing to rank; the load
            // computes the outcome for the current query when it finishes.
            guard !Task.isCancelled, catalog.isLoaded else { return }
            outcome = search.outcome(for: query)
        }
        .sheet(isPresented: $showCreationSheet) { creationSheet }
    }

    // MARK: Browse mode picker

}
