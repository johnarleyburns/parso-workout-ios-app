import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension ExercisePickerView {
    /// Browse / Recents / Popular: the single primary scope. Hidden while searching,
    /// because a query always searches the full catalog (see `searchScopeNote`).
    var tabPicker: some View {
        HStack(spacing: 8) {
            chip("Browse", active: selectedTab == .browse) { selectedTab = .browse }
                .accessibilityIdentifier("picker.tab.browse")
            chip("Recents", active: selectedTab == .recents) { selectedTab = .recents }
                .accessibilityIdentifier("picker.tab.recents")
            chip("Popular", active: selectedTab == .popular) { selectedTab = .popular }
                .accessibilityIdentifier("picker.tab.popular")
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
    }

    /// At most ONE horizontally scrolling row (the active dimension's values) plus
    /// wrapping removable chips. Mode and the secondary dimension live in `filterMenu`.
    var browseControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if trimmedQuery.isEmpty && selectedTab == .browse { primaryFacetRow }
            if filterState.hasFacets { activeConstraintChips }
            if !trimmedQuery.isEmpty && filterState.hasFacets {
                Button { clearFacets() } label: {
                    Label("Search all exercises", systemImage: "magnifyingglass")
                        .frame(minHeight: ExerciseFilterAccessibility.minimumHitTarget.cgFloat)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Removes the muscle group and equipment filters and keeps your search")
                .accessibilityIdentifier("picker.searchAll")
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    var showsBrowseControls: Bool {
        if trimmedQuery.isEmpty { return selectedTab == .browse }
        return filterState.hasFacets
    }

    /// The active dimension's values, e.g. muscle groups when browsing by muscle group.
    var primaryFacetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                switch browseMode {
                case .byMuscleGroup:
                    chip("All", active: selectedGroup == nil) { selectedGroup = nil }
                        .accessibilityIdentifier("picker.filter.all")
                    ForEach(availableGroups) { group in
                        chip(group.displayName, active: selectedGroup == group) {
                            selectedGroup = (selectedGroup == group) ? nil : group
                        }
                        .accessibilityIdentifier("picker.filter.\(group.rawValue)")
                    }
                case .byEquipment:
                    chip("All", active: selectedEquipment == nil) { selectedEquipment = nil }
                        .accessibilityIdentifier("picker.equip.all")
                    ForEach(availableEquipment) { eq in
                        chip(eq.displayName, active: selectedEquipment == eq) {
                            selectedEquipment = (selectedEquipment == eq) ? nil : eq
                        }
                        .accessibilityIdentifier("picker.equip.\(eq.rawValue)")
                    }
                }
            }
        }
    }

    /// Individually removable chips for each active constraint, plus Clear all.
    var activeConstraintChips: some View {
        WrappingChipLayout(spacing: 8) {
            if let eq = selectedEquipment {
                removableChip(eq.displayName) { selectedEquipment = nil }
                    .accessibilityIdentifier("picker.active.equip")
            }
            if let group = selectedGroup {
                removableChip(group.displayName) { selectedGroup = nil }
                    .accessibilityIdentifier("picker.active.group")
            }
            Button { clearAll() } label: {
                Text("Clear all")
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityIdentifier("picker.clearAll")
        }
    }

    func removableChip(_ label: String, _ remove: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); remove() } label: {
            HStack(spacing: 4) {
                Text(label)
                Image(systemName: "xmark.circle.fill")
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(.tint, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ExerciseFilterAccessibility.removeChipLabel(label))
        .accessibilityAddTraits(.isSelected)
    }

    /// Secondary controls (browse mode and the other dimension) in a compact menu.
    var filterMenu: some View {
        Menu {
            if trimmedQuery.isEmpty && selectedTab == .browse {
                Picker("Browse by", selection: $browseMode) {
                    Text("Muscle Group").tag(BrowseMode.byMuscleGroup)
                    Text("Equipment").tag(BrowseMode.byEquipment)
                }
            }
            if !trimmedQuery.isEmpty || browseMode == .byEquipment, selectedTab == .browse || !trimmedQuery.isEmpty {
                Picker("Muscle group", selection: $selectedGroup) {
                    Text("Any").tag(MuscleGroup?.none)
                    ForEach(menuGroups) { Text($0.displayName).tag(Optional($0)) }
                }
            }
            if !trimmedQuery.isEmpty || (browseMode == .byMuscleGroup && selectedGroup != nil) {
                Picker("Equipment", selection: $selectedEquipment) {
                    Text("Any").tag(Equipment?.none)
                    ForEach(menuEquipment) { Text($0.displayName).tag(Optional($0)) }
                }
            }
            if filterState.hasFacets {
                Button("Clear all", role: .destructive) { clearAll() }
            }
        } label: {
            Label("Filter", systemImage: filterState.hasFacets
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Filter exercises")
        .accessibilityIdentifier("picker.filterMenu")
    }

    var menuGroups: [MuscleGroup] {
        if !trimmedQuery.isEmpty { return MuscleGroup.canonicalOrder }
        return availableGroups
    }

    var menuEquipment: [Equipment] {
        if !trimmedQuery.isEmpty { return Equipment.allCases }
        return availableEquipment
    }

    func clearAll() {
        var state = filterState
        state.clearAll()
        selectedTab = .browse; selectedGroup = state.group; selectedEquipment = state.equipment
    }

    func clearFacets() {
        var state = filterState
        state.clearFacets()
        selectedGroup = state.group; selectedEquipment = state.equipment
    }

    func chip(_ label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); tap() } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 44)
                .background(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.background.secondary),
                            in: Capsule())
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: Empty states

    @ViewBuilder
    var noMatchesView: some View {
        if filterState.hasFacets {
            ContentUnavailableView {
                Label("No matches under current filters", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                let facets = [selectedEquipment?.displayName, selectedGroup?.displayName].compactMap { $0 }
                Text(trimmedQuery.isEmpty
                     ? "Nothing matches \(facets.joined(separator: " + "))."
                     : "No results for \u{201C}\(trimmedQuery)\u{201D} with \(facets.joined(separator: " + ")).")
            } actions: {
                Button("Clear filters") { clearFacets() }
                    .accessibilityIdentifier("picker.clearFilters")
            }
        } else {
            ContentUnavailableView.search(text: trimmedQuery)
        }
    }

    // MARK: Rows

    func exerciseRow(_ ex: ExerciseCatalogEntry) -> some View {
        NavigationLink(value: ExercisePickerView.ExerciseDetailRoute.exercise(ex.id)) {
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
                    if let focus = primaryFocusLabel(ex) {
                        Text(focus).font(.caption2.weight(.medium)).foregroundStyle(.tint)
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
        .matchedTransitionSource(id: ex.id, in: searchTransition)
        .accessibilityIdentifier("picker.row.\(ex.name)")
    }

    func muscleSubtitle(_ ex: ExerciseCatalogEntry) -> String? {
        var parts: [String] = []
        if let eq = ex.equipmentValue { parts.append(eq.displayName) }
        if !ex.summaryMuscleGroups.isEmpty {
            parts.append(ex.summaryMuscleGroups.map(\.displayName).joined(separator: ", "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Rows are catalog values; the stored exercise is read only when picked.
    func pick(_ entry: ExerciseCatalogEntry) {
        guard let exercise = ExerciseCatalogSnapshot.exercise(id: entry.id, in: context) else { return }
        finish(with: exercise)
    }

    /// Picker modes complete and dismiss; browse mode only opens the detail.
    func finish(with exercise: Exercise) {
        switch ExerciseSelectionPolicy.outcome(isBrowse: isFind) {
        case .completeAndDismiss:
            completion?(exercise)
            dismiss()
        case .openDetail:
            path.append(.exercise(exercise.id))
        }
    }

    func create() {
        let name = trimmedQuery
        guard !name.isEmpty else { return }
        if let ex = try? WorkoutRepository.findOrCreateExercise(named: name, in: context) {
            appModel.pushSettingsContext()
            finish(with: ex)
        }
    }

    func createConfirmed() {
        let name = trimmedQuery
        guard !name.isEmpty else { return }
        if let ex = try? WorkoutRepository.findOrCreateExercise(
            named: name,
            category: selectedCreationCategory,
            primaryMuscles: Array(selectedCreationMuscles),
            secondaryMuscles: Array(selectedCreationSecondary),
            in: context) {
            appModel.pushSettingsContext()
            showCreationSheet = false
            finish(with: ex)
        }
    }

    var creationSheet: some View {
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
                        selectedCreationMuscles = Set(
                            MuscleGroup.defaults(forCategory: cat).map(\.rawValue))
                    }
                }

                if !selectedCreationMuscles.isEmpty {
                    Section("Muscle Groups (auto-filled from category)") {
                        Text(MuscleGroup.sorted(MuscleGroup.canonicalize(Array(selectedCreationMuscles)))
                            .map(\.displayName).joined(separator: ", "))
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
                if let cat = ExerciseCategory.guess(fromName: trimmedQuery) {
                    selectedCreationCategory = cat
                    selectedCreationMuscles = Set(
                        MuscleGroup.defaults(forCategory: cat).map(\.rawValue))
                } else {
                    selectedCreationCategory = .other
                    selectedCreationMuscles = []
                }
            }
        }
    }
}

private extension Double { var cgFloat: CGFloat { CGFloat(self) } }

/// Left-aligned wrapping layout so selected chips never scroll out of view or
/// shrink under large Dynamic Type.
struct WrappingChipLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(bounds.width, subviews).frames
        for (view, frame) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (frames, CGSize(width: maxX, height: y + rowHeight))
    }
}
