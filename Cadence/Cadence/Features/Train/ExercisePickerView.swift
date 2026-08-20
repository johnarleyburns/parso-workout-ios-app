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

    enum BrowseMode: String, CaseIterable { case byBodyPart, byEquipment }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var query = ""
    /// The snapshot of everything a query implies — results, exact-match flag and
    /// the "good match" suggestion — recomputed only when the debounced query
    /// changes, never on a redraw (field test 2026-08-19 #4).
    @State private var search = ExercisePickerSearch()
    @State private var outcome = ExercisePickerSearch.Outcome.empty
    @State private var facetIndex = ExerciseFacetIndex<Exercise>([])
    @State private var selectedTab: PickerTab = .recents
    @State private var selectedPart: BodyPart?
    @State private var selectedEquipment: Equipment?
    @State private var browseMode: BrowseMode = .byBodyPart
    @State private var browseAll = false
    @State private var recents: [Exercise] = []
    @State private var showCreationSheet = false
    @State private var selectedCreationCategory: ExerciseCategory = .other
    @State private var selectedCreationMuscles: Set<String> = []
    @State private var selectedCreationSecondary: Set<String> = []
    @State private var selectedCreationParts: Set<BodyPart> = []
    let action: PickAction
    let onPick: (Exercise) -> Void

    init(action: PickAction = .add, onPick: @escaping (Exercise) -> Void) {
        self.action = action
        self.onPick = onPick
    }

    private var trimmedQuery: String { outcome.query }

    private var popular: [Exercise] { search.popular }

    private var filtered: [Exercise] {
        if !trimmedQuery.isEmpty { return outcome.results }
        switch selectedTab {
        case .recents: return recents
        case .popular: return browseAll ? exercises : popular
        case .browse:
            switch browseMode {
            case .byBodyPart:
                if let part = selectedPart { return facetIndex.exercises(for: part, equipment: selectedEquipment) }
                return exercises
            case .byEquipment:
                if let eq = selectedEquipment { return facetIndex.exercises(forEquipment: eq, bodyPart: selectedPart) }
                return exercises
            }
        }
    }

    private var availableEquipment: [Equipment] {
        switch browseMode {
        case .byBodyPart:
            guard let part = selectedPart else { return [] }
            return facetIndex.equipment(for: part)
        case .byEquipment:
            return Equipment.allCases.filter { !facetIndex.exercises(forEquipment: $0).isEmpty }
        }
    }

    private var availableParts: [BodyPart] {
        switch browseMode {
        case .byBodyPart:
            return BodyPart.allCases
        case .byEquipment:
            guard let eq = selectedEquipment else { return [] }
            return facetIndex.bodyParts(forEquipment: eq)
        }
    }

    private func rebuildIndexIfNeeded() {
        guard search.rebuildIfNeeded(exercises) else { return }
        facetIndex = ExerciseFacetIndex(exercises)
        if !query.isEmpty { outcome = search.outcome(for: query) }
    }

    private var grouped: [(ExerciseCategory, [Exercise])] {
        let dict = Dictionary(grouping: filtered) { $0.categoryValue ?? .other }
        return ExerciseCategory.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items.sorted { $0.name < $1.name })
        }
    }

    private var exactMatchExists: Bool { outcome.exactMatch }

    private var bestLibraryMatch: Exercise? { outcome.bestMatch }

    private var showsGrouped: Bool {
        selectedTab == .browse && trimmedQuery.isEmpty && selectedPart == nil && selectedEquipment == nil
    }

    private var showsFilterChips: Bool {
        selectedTab == .browse && trimmedQuery.isEmpty
    }

    private var showsSubFilter: Bool {
        showsFilterChips && browseMode == .byBodyPart
            && selectedPart != nil && availableEquipment.count > 1
    }

    private var showsSubFilterInverted: Bool {
        showsFilterChips && browseMode == .byEquipment
            && selectedEquipment != nil && availableParts.count > 0
    }

    private var sectionTitle: String {
        if !trimmedQuery.isEmpty { return "Results" }
        switch selectedTab {
        case .recents: return "Recent"
        case .popular: return browseAll ? "All" : "Popular"
        case .browse:
            switch browseMode {
            case .byBodyPart:
                if let part = selectedPart {
                    if let eq = selectedEquipment { return "\(part.displayName)  \(eq.displayName)" }
                    return part.displayName
                }
                return "All"
            case .byEquipment:
                if let eq = selectedEquipment {
                    if let part = selectedPart { return "\(eq.displayName)  \(part.displayName)" }
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
                        if showsSubFilterInverted { bodyPartSubChips }
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
        .onChange(of: selectedPart) { _, _ in selectedEquipment = nil }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .browse { selectedEquipment = nil; selectedPart = nil }
            if newTab != .browse { selectedPart = nil; selectedEquipment = nil }
            if newTab == .recents { loadRecents() }
        }
        .onChange(of: browseMode) { _, _ in selectedEquipment = nil; selectedPart = nil }
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

    private var browseModePicker: some View {
        Picker("Browse by", selection: $browseMode) {
            Text("By Body Part").tag(BrowseMode.byBodyPart)
            Text("By Equipment").tag(BrowseMode.byEquipment)
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }

    // MARK: Filter chips

    private var filterChips: some View {
        Group {
            switch browseMode {
            case .byBodyPart: bodyPartFilterChips
            case .byEquipment: equipmentFilterChips
            }
        }
    }

    private var bodyPartFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: selectedPart == nil) { selectedPart = nil }
                    .accessibilityIdentifier("picker.filter.all")
                ForEach(BodyPart.allCases) { part in
                    chip(part.displayName, active: selectedPart == part) {
                        selectedPart = (selectedPart == part) ? nil : part
                    }
                    .accessibilityIdentifier("picker.filter.\(part.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 0))
    }

    private var equipmentFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: selectedEquipment == nil) { selectedEquipment = nil }
                    .accessibilityIdentifier("picker.equip.all")
                ForEach(availableEquipment) { eq in
                    chip(eq.displayName, active: selectedEquipment == eq) {
                        selectedEquipment = (selectedEquipment == eq) ? nil : eq
                    }
                    .accessibilityIdentifier("picker.equip.\(eq.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 0))
    }

    // MARK: Sub-filter chips (byBodyPart: equipment, byEquipment: body part)

    private var equipmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: selectedEquipment == nil) { selectedEquipment = nil }
                    .accessibilityIdentifier("picker.equip.all")
                ForEach(availableEquipment) { eq in
                    chip(eq.displayName, active: selectedEquipment == eq) {
                        selectedEquipment = (selectedEquipment == eq) ? nil : eq
                    }
                    .accessibilityIdentifier("picker.equip.\(eq.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 6, trailing: 0))
    }

    private var bodyPartSubChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: selectedPart == nil) { selectedPart = nil }
                    .accessibilityIdentifier("picker.filter.all")
                ForEach(availableParts) { part in
                    chip(part.displayName, active: selectedPart == part) {
                        selectedPart = (selectedPart == part) ? nil : part
                    }
                    .accessibilityIdentifier("picker.filter.\(part.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 6, trailing: 0))
    }

    private func chip(_ label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); tap() } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.background.secondary),
                            in: Capsule())
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Rows

    private func exerciseRow(_ ex: Exercise) -> some View {
        NavigationLink(value: ex) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(ex.name)
                        if ex.isCustom {
                            Text("Custom").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if let muscles = muscleSubtitle(ex) {
                        Text(muscles).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "info.circle")
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("picker.info.\(ex.name)")
                    .accessibilityLabel("View \(ex.name) details")
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("picker.row.\(ex.name)")
    }

    private func muscleSubtitle(_ ex: Exercise) -> String? {
        let ids = ex.primaryMuscles.isEmpty ? ex.muscleGroups : ex.primaryMuscles
        guard !ids.isEmpty else { return nil }
        return ids.prefix(3).map { id in
            id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        }.joined(separator: ", ")
    }

    private func create() {
        let name = trimmedQuery
        guard !name.isEmpty else { return }
        if let ex = try? WorkoutRepository.findOrCreateExercise(named: name, in: context) {
            appModel.pushSettingsContext()
            onPick(ex); dismiss()
        }
    }

    private func createConfirmed() {
        let name = trimmedQuery
        guard !name.isEmpty else { return }
        if let ex = try? WorkoutRepository.findOrCreateExercise(
            named: name,
            category: selectedCreationCategory,
            primaryMuscles: Array(selectedCreationMuscles),
            secondaryMuscles: Array(selectedCreationSecondary),
            in: context) {
            appModel.pushSettingsContext()
            onPick(ex)
            showCreationSheet = false
            dismiss()
        }
    }

    private var creationSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Name").foregroundStyle(.secondary)
                        Spacer()
                        Text(trimmedQuery).bold()
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCreationCategory) {
                        ForEach(ExerciseCategory.allCases.filter { $0 != .cardio && $0 != .plyometrics }) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedCreationCategory) { _, cat in
                        let muscles = BodyPart.defaultMuscles(forCategory: cat)
                        selectedCreationMuscles = Set(muscles)
                        selectedCreationParts = BodyPart.parts(forCategory: cat)
                    }
                }

                if !selectedCreationParts.isEmpty {
                    Section("Body Parts (auto-filled from category)") {
                        Text(selectedCreationParts.sorted { $0.rawValue < $1.rawValue }
                            .map(\.displayName).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !selectedCreationMuscles.isEmpty {
                    Section("Muscles (auto-filled from category)") {
                        Text(selectedCreationMuscles.sorted().map { id in
                            id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
                        }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreationSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create & Add") { createConfirmed() }
                }
            }
            .onAppear {
                if let cat = BodyPart.guessCategory(from: trimmedQuery) {
                    selectedCreationCategory = cat
                    selectedCreationMuscles = Set(BodyPart.defaultMuscles(forCategory: cat))
                    selectedCreationParts = BodyPart.parts(forCategory: cat)
                } else {
                    selectedCreationCategory = .other
                    selectedCreationMuscles = []
                    selectedCreationParts = []
                }
            }
        }
    }

    private func loadRecents() {
        if let r = try? WorkoutRepository.recentlyUsedExercises(context) {
            recents = r
        }
    }
}
