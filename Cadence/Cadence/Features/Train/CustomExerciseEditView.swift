import SwiftUI
import CadenceCore

/// Lets users tag a custom exercise with muscle group, muscles, equipment, and category
/// (Phase 5). Opened from ExerciseDetailView when the exercise is user-created.
struct CustomExerciseEditView: View {
    let exercise: Exercise
    var onSave: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEquipment: Equipment?
    @State private var selectedCategory: ExerciseCategory?
    @State private var selectedMechanics: Mechanics?
    @State private var selectedForce: Force?
    @State private var selectedBodyParts: Set<BodyPart> = []
    @State private var selectedMuscleIDs: Set<String> = []
    @State private var selectedSecondaryIDs: Set<String> = []

    private var allMuscles: [Muscle] { MuscleCatalog.all }

    var body: some View {
        NavigationStack {
            Form {
                Section("Muscle Groups") {
                    bodyPartChips
                    Text("Tap a muscle group to select its primary muscles. Fine-tune in the Muscles section below.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Equipment") {
                    Picker("Equipment", selection: $selectedEquipment) {
                        Text("None").tag(Equipment?.none)
                        ForEach(Equipment.allCases) { eq in
                            Text(eq.displayName).tag(Optional(eq))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Category") {
                    Picker("Movement Split", selection: $selectedCategory) {
                        Text("None").tag(ExerciseCategory?.none)
                        ForEach(ExerciseCategory.allCases) { cat in
                            Text(cat.displayName).tag(Optional(cat))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Mechanics") {
                    Picker("Mechanics", selection: $selectedMechanics) {
                        Text("None").tag(Mechanics?.none)
                        ForEach(Mechanics.allCases, id: \.self) { m in
                            Text(m.rawValue.capitalized).tag(Optional(m))
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Force") {
                    Picker("Force", selection: $selectedForce) {
                        Text("None").tag(Force?.none)
                        ForEach(Force.allCases, id: \.self) { f in
                            Text(f.rawValue.capitalized).tag(Optional(f))
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Primary Muscles") {
                    muscleGrid(selected: $selectedMuscleIDs)
                }

                Section("Secondary Muscles") {
                    muscleGrid(selected: $selectedSecondaryIDs)
                }
            }
            .navigationTitle("Edit \(exercise.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                        .accessibilityIdentifier("edit.save")
                }
            }
            .onAppear { loadExisting() }
            .onChange(of: selectedBodyParts) { _, parts in applyBodyPartSelection(parts) }
        }
        .presentationDetents([.large])
    }

    // MARK: - Body part chips

    private var bodyPartChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(BodyPart.allCases) { part in
                chip(part.displayName, selected: selectedBodyParts.contains(part)) {
                    if selectedBodyParts.contains(part) {
                        selectedBodyParts.remove(part)
                    } else {
                        selectedBodyParts.insert(part)
                    }
                }
            }
        }
    }

    private func applyBodyPartSelection(_ parts: Set<BodyPart>) {
        for part in parts {
            let muscleIDs = bodyPartMuscleIDs[part] ?? []
            selectedMuscleIDs.formUnion(muscleIDs)
        }
    }

    private var bodyPartMuscleIDs: [BodyPart: Set<String>] {
        var map: [BodyPart: Set<String>] = [:]
        for muscle in allMuscles {
            guard let bp = BodyPart.part(forMuscleID: muscle.id) else { continue }
            map[bp, default: []].insert(muscle.id)
        }
        return map
    }

    // MARK: - Muscle grid

    private func muscleGrid(selected: Binding<Set<String>>) -> some View {
        let grouped = Dictionary(grouping: allMuscles, by: { $0.region })
        return ForEach(BodyRegion.allCases, id: \.self) { region in
            if let muscles = grouped[region], !muscles.isEmpty {
                Section(region.displayName) {
                    muscleChips(muscles, selected: selected)
                }
            }
        }
    }

    private func muscleChips(_ muscles: [Muscle], selected: Binding<Set<String>>) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(muscles) { muscle in
                let isSelected = selected.wrappedValue.contains(muscle.id)
                chip(muscle.scientific, selected: isSelected) {
                    if isSelected {
                        selected.wrappedValue.remove(muscle.id)
                    } else {
                        selected.wrappedValue.insert(muscle.id)
                    }
                }
            }
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiarySystemFill)), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Load / save

    private func loadExisting() {
        selectedEquipment = exercise.equipmentValue
        selectedCategory = exercise.categoryValue
        selectedMechanics = exercise.mechanicsValue
        selectedForce = exercise.forceValue
        selectedMuscleIDs = Set(exercise.primaryMuscles)
        selectedSecondaryIDs = Set(exercise.secondaryMuscles)

        let bpSet = Set(BodyPart.allCases.filter { bp in
            let ids = bodyPartMuscleIDs[bp] ?? []
            return !selectedMuscleIDs.intersection(ids).isEmpty
        })
        selectedBodyParts = bpSet
    }

    private func save() {
        _ = try? WorkoutRepository.updateExercise(
            exercise,
            category: selectedCategory,
            equipment: selectedEquipment,
            mechanics: selectedMechanics,
            force: selectedForce,
            primaryMuscles: Array(selectedMuscleIDs),
            secondaryMuscles: Array(selectedSecondaryIDs),
            in: context)
        onSave?()
    }
}

private extension BodyRegion {
    static var allCases: [BodyRegion] { [.chest, .back, .shoulders, .arms, .core, .legs, .glutes] }
    var displayName: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .arms: "Arms"
        case .core: "Core"
        case .legs: "Legs"
        case .glutes: "Glutes"
        case .fullBody: "Full Body"
        }
    }
}
