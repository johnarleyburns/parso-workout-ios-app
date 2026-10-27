import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension ExercisePickerView {
    /// Browse / Recents / Popular, as a List row so it shares the exercise rows'
    /// horizontal margins. Rendered as the same large chip buttons as the
    /// muscle/equipment filters (field report: choose-exercise selector styles
    /// were inconsistent with the rest of the app).
    var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Browse", active: selectedTab == .browse) { selectedTab = .browse }
                    .accessibilityIdentifier("picker.tab.browse")
                chip("Recents", active: selectedTab == .recents) { selectedTab = .recents }
                    .accessibilityIdentifier("picker.tab.recents")
                chip("Popular", active: selectedTab == .popular) { selectedTab = .popular }
                    .accessibilityIdentifier("picker.tab.popular")
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    /// The browse-mode control and its chip rows in one List row, so there is no
    /// section gap above or below the muscle/equipment controls.
    var browseControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            browseModePicker
            filterChips
            if showsSubFilter { equipmentChips }
            if showsSubFilterInverted { muscleGroupSubChips }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    var browseModePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("By Muscle Group", active: browseMode == .byMuscleGroup) { browseMode = .byMuscleGroup }
                    .accessibilityIdentifier("picker.browseMode.muscleGroup")
                chip("By Equipment", active: browseMode == .byEquipment) { browseMode = .byEquipment }
                    .accessibilityIdentifier("picker.browseMode.equipment")
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Filter chips

    var filterChips: some View {
        Group {
            switch browseMode {
            case .byMuscleGroup: muscleGroupFilterChips
            case .byEquipment: equipmentFilterChips
            }
        }
    }

    var muscleGroupFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: selectedGroup == nil) { selectedGroup = nil }
                    .accessibilityIdentifier("picker.filter.all")
                ForEach(availableGroups) { group in
                    chip(group.displayName, active: selectedGroup == group) {
                        selectedGroup = (selectedGroup == group) ? nil : group
                    }
                    .accessibilityIdentifier("picker.filter.\(group.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 0))
    }

    var equipmentFilterChips: some View {
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

    // MARK: Sub-filter chips (byMuscleGroup: equipment, byEquipment: muscle group)

    var equipmentChips: some View {
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

    var muscleGroupSubChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: selectedGroup == nil) { selectedGroup = nil }
                    .accessibilityIdentifier("picker.filter.all")
                ForEach(availableGroups) { group in
                    chip(group.displayName, active: selectedGroup == group) {
                        selectedGroup = (selectedGroup == group) ? nil : group
                    }
                    .accessibilityIdentifier("picker.filter.\(group.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 6, trailing: 0))
    }

    func chip(_ label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
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
        guard !ex.summaryMuscleGroups.isEmpty else { return nil }
        return ex.summaryMuscleGroups.map(\.displayName).joined(separator: ", ")
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
