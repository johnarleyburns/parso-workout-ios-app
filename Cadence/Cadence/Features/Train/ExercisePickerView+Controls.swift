import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension ExercisePickerView {
    var browseModePicker: some View {
        Picker("Browse by", selection: $browseMode) {
            Text("By Body Part").tag(BrowseMode.byBodyPart)
            Text("By Equipment").tag(BrowseMode.byEquipment)
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }

    // MARK: Filter chips

    var filterChips: some View {
        Group {
            switch browseMode {
            case .byBodyPart: bodyPartFilterChips
            case .byEquipment: equipmentFilterChips
            }
        }
    }

    var bodyPartFilterChips: some View {
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

    // MARK: Sub-filter chips (byBodyPart: equipment, byEquipment: body part)

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

    var bodyPartSubChips: some View {
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

    func exerciseRow(_ ex: Exercise) -> some View {
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

    func muscleSubtitle(_ ex: Exercise) -> String? {
        let ids = ex.primaryMuscles.isEmpty ? ex.muscleGroups : ex.primaryMuscles
        guard !ids.isEmpty else { return nil }
        return ids.prefix(3).map { id in
            id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        }.joined(separator: ", ")
    }

    func create() {
        let name = trimmedQuery
        guard !name.isEmpty else { return }
        if let ex = try? WorkoutRepository.findOrCreateExercise(named: name, in: context) {
            appModel.pushSettingsContext()
            onPick(ex); dismiss()
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
            onPick(ex)
            showCreationSheet = false
            dismiss()
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

    func loadRecents() {
        if let r = try? WorkoutRepository.recentlyUsedExercises(context) {
            recents = r
        }
    }
}
