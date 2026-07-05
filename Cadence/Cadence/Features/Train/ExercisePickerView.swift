import SwiftUI
import SwiftData
import CadenceCore

/// Searchable exercise library picker (FR-1.1, expanded feedback batch 8). To keep a
/// large catalog usable it leads with a curated **Popular** shortlist and hides the
/// long tail behind **Browse all** + search; a row of **body-part filter chips** and
/// muscle subtitles make movements discoverable ("show me lats"). Each row's info
/// button opens an in-app **ExerciseDetailView** with the public-domain image,
/// muscles, and instructions (P2 — no external links). An inline "Create '<query>'"
/// row adds a custom exercise.
struct ExercisePickerView: View {
    enum PickAction {
        case add
        case swap
        case use

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

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var query = ""
    /// Debounced mirror of `query`; the expensive ranking keys off this so typing
    /// stays smooth (the ranking never runs on every keystroke).
    @State private var debouncedQuery = ""
    /// Normalization is precomputed once here, so per-keystroke ranking is cheap.
    @State private var searchIndex = ExerciseSearchIndex<Exercise>([])
    /// Body-part → exercises / equipment, precomputed once so the equipment
    /// sub-filter is an instant lookup (not an O(catalog) scan per render).
    @State private var facetIndex = ExerciseFacetIndex<Exercise>([])
    @State private var indexedCount = -1
    @State private var selectedPart: BodyPart?
    /// Second-level filter under the selected body part (feedback: hundreds of
    /// movements per part). nil ⇒ all equipment for that part.
    @State private var selectedEquipment: Equipment?
    @State private var browseAll = false
    let action: PickAction
    let onPick: (Exercise) -> Void

    init(action: PickAction = .add, onPick: @escaping (Exercise) -> Void) {
        self.action = action
        self.onPick = onPick
    }

    private var trimmedQuery: String { debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The popular shortlist, resolved against the seeded store (in catalog order).
    private var popular: [Exercise] {
        let byName = Dictionary(exercises.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        return ExerciseLibrary.popularNames.compactMap { byName[$0.lowercased()] }
    }

    /// What to show: a search beats everything; then a body-part filter; else the
    /// popular shortlist (until "Browse all" reveals the full grouped catalog).
    private var filtered: [Exercise] {
        if !trimmedQuery.isEmpty { return searchIndex.rank(trimmedQuery) }
        if let part = selectedPart { return facetIndex.exercises(for: part, equipment: selectedEquipment) }
        return browseAll ? exercises : popular
    }

    /// Equipment types available for the selected body part, in canonical order.
    private var availableEquipment: [Equipment] {
        guard let part = selectedPart else { return [] }
        return facetIndex.equipment(for: part)
    }

    /// Rebuilds the normalized search index when the catalog size changes (first
    /// load, custom exercise added). Cheap-guarded so it never runs per keystroke.
    private func rebuildIndexIfNeeded() {
        guard exercises.count != indexedCount else { return }
        searchIndex = ExerciseSearchIndex(exercises)
        facetIndex = ExerciseFacetIndex(exercises)
        indexedCount = exercises.count
    }

    private var grouped: [(ExerciseCategory, [Exercise])] {
        let dict = Dictionary(grouping: filtered) { $0.categoryValue ?? .other }
        return ExerciseCategory.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items.sorted { $0.name < $1.name })
        }
    }

    private var exactMatchExists: Bool {
        exercises.contains { $0.name.compare(trimmedQuery, options: .caseInsensitive) == .orderedSame }
    }

    /// Group the flat list (search/filter/popular) into categories only when browsing
    /// the whole catalog; otherwise show one flat, ranked section.
    private var showsGrouped: Bool { browseAll && trimmedQuery.isEmpty && selectedPart == nil }

    var body: some View {
        NavigationStack {
            List {
                filterChips
                if showsEquipmentFilter { equipmentChips }

                if !trimmedQuery.isEmpty && !exactMatchExists {
                    Section {
                        Button { create() } label: {
                            Label("Create “\(query)”", systemImage: "plus.circle.fill")
                        }
                        .accessibilityIdentifier("picker.create")
                    }
                }

                if showsGrouped {
                    ForEach(grouped, id: \.0) { cat, items in
                        Section(cat.displayName) { ForEach(items) { exerciseRow($0) } }
                    }
                } else {
                    Section(sectionTitle) { ForEach(filtered) { exerciseRow($0) } }
                    if !browseAll && trimmedQuery.isEmpty && selectedPart == nil {
                        Section {
                            Button { browseAll = true } label: {
                                Label("Browse all exercises", systemImage: "square.grid.2x2")
                            }
                            .accessibilityIdentifier("picker.browseAll")
                        }
                    }
                }
            }
            .navigationTitle(action.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .searchable(text: $query, prompt: "Search name, muscle, or equipment")
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailView(exercise: exercise, actionTitle: action.detailActionTitle) { picked in
                    dismiss()
                    onPick(picked)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("picker.cancel")
                }
            }
        }
        .accessibilityIdentifier("picker.search")
        .onAppear { rebuildIndexIfNeeded() }
        .onChange(of: exercises.count) { _, _ in rebuildIndexIfNeeded() }
        // Changing body part invalidates the equipment sub-filter (each part offers
        // a different equipment set), so reset it.
        .onChange(of: selectedPart) { _, _ in selectedEquipment = nil }
        // Debounce: coalesce keystrokes so ranking runs after a brief pause, not
        // on every character. A cleared query updates immediately.
        .task(id: query) {
            if query.isEmpty { debouncedQuery = ""; return }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            debouncedQuery = query
        }
    }

    private var sectionTitle: String {
        if !trimmedQuery.isEmpty { return "Results" }
        if let part = selectedPart {
            if let eq = selectedEquipment { return "\(part.displayName) · \(eq.displayName)" }
            return part.displayName
        }
        return "Popular"
    }

    // MARK: Body-part filter chips

    private var filterChips: some View {
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

    // MARK: Equipment sub-filter chips

    /// The second chip row only earns its space when a body part is selected, no
    /// search is active, and the part actually offers more than one equipment type.
    private var showsEquipmentFilter: Bool {
        trimmedQuery.isEmpty && selectedPart != nil && availableEquipment.count > 1
    }

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

    /// A single `NavigationLink` per row. Making the whole row the tap target (vs a
    /// `Button` inside a `.searchable` `List`) fixes the "tap does nothing" bug: a
    /// button's first tap was being consumed by the keyboard dismissal, whereas a
    /// List `NavigationLink` registers on the first tap with the keyboard up.
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

    /// Friendly muscle list from the exercise's primary muscles ("upper-chest" →
    /// "Upper Chest"), so a glance shows what it trains (batch 8).
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
            onPick(ex); dismiss()
        }
    }
}
