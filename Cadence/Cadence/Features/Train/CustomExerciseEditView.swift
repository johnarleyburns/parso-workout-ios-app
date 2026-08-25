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
    @State private var selectedMuscleIDs: Set<String> = []
    @State private var selectedSecondaryIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("The muscles this movement trains directly — what its sets count toward.")
                        .font(.caption).foregroundStyle(.secondary)
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
        }
        .presentationDetents([.large])
    }

    // MARK: - Muscle grid

    /// One chip per `MuscleGroup`, grouped by body region for scanability. The
    /// groups are the same dimension the coach counts volume in, so what the user
    /// tags here is exactly what their sets credit (decision D2).
    private func muscleGrid(selected: Binding<Set<String>>) -> some View {
        let grouped = Dictionary(grouping: MuscleGroup.canonicalOrder, by: \.region)
        return ForEach(BodyRegion.allCases, id: \.self) { region in
            if let groups = grouped[region], !groups.isEmpty {
                Section(region.displayName) {
                    muscleChips(MuscleGroup.sorted(groups), selected: selected)
                }
            }
        }
    }

    private func muscleChips(_ groups: [MuscleGroup], selected: Binding<Set<String>>) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(groups) { group in
                let isSelected = selected.wrappedValue.contains(group.rawValue)
                chip(group.displayName, selected: isSelected) {
                    if isSelected {
                        selected.wrappedValue.remove(group.rawValue)
                    } else {
                        selected.wrappedValue.insert(group.rawValue)
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
        // Canonicalize on load so an exercise stored with pre-DB++ muscle ids
        // ("quads", "delts") shows its chips selected rather than looking untagged.
        selectedMuscleIDs = Set(MuscleGroup.canonicalize(exercise.primaryMuscles).map(\.rawValue))
        selectedSecondaryIDs = Set(MuscleGroup.canonicalize(exercise.secondaryMuscles).map(\.rawValue))
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
