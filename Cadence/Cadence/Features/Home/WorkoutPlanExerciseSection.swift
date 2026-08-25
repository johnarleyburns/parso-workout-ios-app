import SwiftUI
import CadenceCore
import CadenceFeatures

/// One planned exercise as a Home-rhythm card. Editable outside a `List`, so
/// per-set deletion is an explicit destructive button rather than a swipe
/// (field test 2026-08-18 #5). With partners on the roster it also edits each
/// performer's own reps (field test 2026-08-18 #4).
struct WorkoutPlanExerciseSection: View {
    @Binding var exercise: EditableExercise
    let unit: MeasurementUnitPreference
    let exerciseInfo: Exercise?
    let onSwap: () -> Void
    let onRemove: () -> Void

    /// nil is the owner ("Me"), which is also the default selection.
    @State private var selectedPerformerID: UUID?
    @State private var showInfo = false
    @State private var showRepSchemes = false

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardHeadingSpacing)) {
            header
            if performerPlans.count > 1 { performerPicker }
            VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
                ForEach(Array(editedSets.enumerated()), id: \.element.id) { index, set in
                    setRow(binding(forSet: set.id), at: index)
                }
                if isEditingOwner {
                    Button {
                        let last = exercise.sets.last
                        exercise.sets.append(EditableSet(targetReps: last?.targetReps ?? 10,
                                                         targetWeight: last?.targetWeight))
                        exercise = PartnerPlanResolver.aligned(exercise)
                    } label: {
                        Label("Add Set", systemImage: "plus").font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("editor.addSet.\(exercise.name)")
                } else {
                    // Decision D12: a partner works in on the owner's sets, so the
                    // set COUNT is the owner's to change, never the partner's.
                    Text("Set count follows your plan — a partner works in on your sets.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .workoutPlanCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.exercise.\(exercise.name)")
    }

    private var header: some View {
        HStack {
            Text(exercise.name).font(.headline)
            Spacer()
            if exerciseInfo != nil {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Exercise info")
                .accessibilityIdentifier("editor.exerciseInfo.\(exercise.name)")
            }
            Menu {
                Button(action: onSwap) {
                    Label("Swap Exercise", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("editor.swapExercise.\(exercise.name)")

                Button { showRepSchemes = true } label: {
                    Label("Change Rep Structure", systemImage: "list.number")
                }

                Button(role: .destructive, action: onRemove) {
                    Label("Remove Exercise", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityIdentifier("editor.exerciseMenu.\(exercise.name)")
            .accessibilityLabel("Exercise options")
        }
        .sheet(isPresented: $showInfo) {
            if let exerciseInfo {
                NavigationStack { ExerciseDetailView(exercise: exerciseInfo) }
            }
        }
        .sheet(isPresented: $showRepSchemes) {
            RepSchemeSheet(current: editedSets.map(\.targetReps)) { reps in
                replaceSelectedSets(with: reps)
            }
        }
    }

    /// Which performer's plan the set rows below are editing. "Me" first.
    private var performerPicker: some View {
        Picker("Performer", selection: $selectedPerformerID) {
            ForEach(performerPlans) { plan in
                Text(plan.name).tag(plan.performerID)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("editor.performerPicker.\(exercise.name)")
    }

    private var performerPlans: [EditablePerformerPlan] {
        PlanFormatting.orderedPerformerPlans(exercise)
    }

    private var isEditingOwner: Bool { selectedPerformerID == nil }

    /// The owner edits `exercise.sets` (the source of truth for set count); a
    /// partner edits their own plan.
    private var editedSets: [EditableSet] {
        guard !isEditingOwner,
              let plan = exercise.performerPlans.first(where: { $0.performerID == selectedPerformerID })
        else { return exercise.sets }
        return plan.sets
    }

    /// `BW` only for movements that really are bodyweight; an unresolved load on a
    /// loaded lift is an em dash (field test 2026-08-18 #2, decision D4).
    private func loadLabel(for set: EditableSet) -> String {
        PlanFormatting.loadLabel(targetWeightKg: set.targetWeight,
                                 isBodyweight: ExerciseLoading.isBodyweight(named: exercise.name),
                                 unit: unit)
    }

    /// Identity-keyed so deleting a set never leaves a row bound to a stale index.
    private func binding(forSet id: UUID) -> Binding<EditableSet> {
        Binding(
            get: { editedSets.first { $0.id == id } ?? EditableSet(targetReps: 10, targetWeight: nil) },
            set: { newValue in
                if isEditingOwner {
                    guard let i = exercise.sets.firstIndex(where: { $0.id == id }) else { return }
                    exercise.sets[i] = newValue
                    exercise = PartnerPlanResolver.aligned(exercise)
                } else {
                    guard let p = exercise.performerPlans.firstIndex(where: { $0.performerID == selectedPerformerID }),
                          let i = exercise.performerPlans[p].sets.firstIndex(where: { $0.id == id })
                    else { return }
                    exercise.performerPlans[p].sets[i] = newValue
                }
            })
    }

    private func setRow(_ set: Binding<EditableSet>, at index: Int) -> some View {
        HStack {
            Stepper("Reps: \(set.wrappedValue.targetReps)", value: set.targetReps, in: 1...100)
                .frame(maxWidth: .infinity)
            LoadEditor(set: set, unit: unit, exerciseName: exercise.name)
            if isEditingOwner {
                Button(role: .destructive) {
                    let id = set.wrappedValue.id
                    exercise.sets.removeAll { $0.id == id }
                    exercise = PartnerPlanResolver.aligned(exercise)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(exercise.sets.count <= 1)
                .accessibilityIdentifier("editor.removeSet.\(exercise.name).\(index)")
                .accessibilityLabel("Remove set \(index + 1)")
            }
        }
        // `.contain` keeps the stepper and the remove button individually
        // addressable under the row's own identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.performerSet.\(exercise.name).\(selectedPerformerName).\(index)")
    }

    private func replaceSelectedSets(with reps: [Int]) {
        guard !reps.isEmpty else { return }
        if isEditingOwner {
            let old = exercise.sets
            exercise.sets = reps.enumerated().map { index, rep in
                let prior = old.indices.contains(index) ? old[index] : old.last
                return EditableSet(targetReps: rep, targetWeight: prior?.targetWeight,
                                   loadMode: prior?.loadMode ?? .straight,
                                   oneRepMaxPercent: prior?.oneRepMaxPercent)
            }
            exercise = PartnerPlanResolver.aligned(exercise)
        } else if let p = exercise.performerPlans.firstIndex(where: { $0.performerID == selectedPerformerID }) {
            let old = exercise.performerPlans[p].sets
            exercise.performerPlans[p].sets = reps.enumerated().map { index, rep in
                let prior = old.indices.contains(index) ? old[index] : old.last
                return EditableSet(targetReps: rep, targetWeight: prior?.targetWeight,
                                   loadMode: prior?.loadMode ?? .straight,
                                   oneRepMaxPercent: prior?.oneRepMaxPercent)
            }
        }
    }

    private var selectedPerformerName: String {
        exercise.performerPlans.first { $0.performerID == selectedPerformerID }?.name ?? "Me"
    }
}

private struct LoadEditor: View {
    @Binding var set: EditableSet
    let unit: MeasurementUnitPreference
    let exerciseName: String
    @State private var showingEditor = false

    var body: some View {
        Button { showingEditor = true } label: {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Load \(label)")
        .sheet(isPresented: $showingEditor) {
            NavigationStack { LoadEditorSheet(set: $set, unit: unit, exerciseName: exerciseName) }
        }
    }

    private var label: String {
        switch set.loadMode {
        case .bodyweight: return "BW"
        case .percentageOfOneRepMax:
            return set.oneRepMaxPercent.map { "\(Int($0))% 1RM" } ?? "% 1RM"
        case .straight:
            guard let weight = set.targetWeight else { return "Set load" }
            return Format.weight(weight, unit: unit, decimals: 0)
        }
    }
}

private struct LoadEditorSheet: View {
    @Binding var set: EditableSet
    let unit: MeasurementUnitPreference
    let exerciseName: String
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var percentText = ""
    @State private var oneRepMaxText = ""

    var body: some View {
        Form {
            Picker("Load", selection: $set.loadMode) {
                Text("Straight weight").tag(EditableLoadMode.straight)
                Text("% of 1RM").tag(EditableLoadMode.percentageOfOneRepMax)
                Text("Bodyweight").tag(EditableLoadMode.bodyweight)
            }
            if set.loadMode == .straight {
                TextField("Weight (\(unit.abbreviation))", text: $weightText)
                    .keyboardType(.decimalPad)
            } else if set.loadMode == .percentageOfOneRepMax {
                TextField("Percent of 1RM", text: $percentText).keyboardType(.decimalPad)
                TextField("Your 1RM (\(unit.abbreviation))", text: $oneRepMaxText).keyboardType(.decimalPad)
                if let weight = calculatedWeight {
                    Text("Target: \(Format.weight(weight, unit: unit, decimals: 1))")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No external load; the session will cue bodyweight.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Set load")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { save(); dismiss() }
            }
        }
        .onAppear {
            weightText = set.targetWeight.map { String(format: "%.2f", WorkoutMath.display($0, in: unit)) } ?? ""
            percentText = set.oneRepMaxPercent.map { String(format: "%.0f", $0) } ?? ""
            oneRepMaxText = set.oneRepMaxPercent.flatMap { _ in
                set.targetWeight.map {
                    String(format: "%.2f", WorkoutMath.display($0, in: unit) / ((Double(percentText) ?? 100.0) * 0.01))
                }
            } ?? ""
        }
    }

    private var calculatedWeight: Double? {
        guard let percent = Double(percentText), let max = Double(oneRepMaxText), percent > 0, max > 0 else { return nil }
        return WorkoutMath.canonical(max, from: unit) * percent / 100
    }

    private func save() {
        switch set.loadMode {
        case .straight:
            set.targetWeight = Double(weightText).map { WorkoutMath.canonical($0, from: unit) }
            set.oneRepMaxPercent = nil
        case .percentageOfOneRepMax:
            set.oneRepMaxPercent = Double(percentText)
            set.targetWeight = calculatedWeight
        case .bodyweight:
            set.targetWeight = nil
            set.oneRepMaxPercent = nil
        }
    }
}

private struct RepSchemeSheet: View {
    let current: [Int]
    let onSelect: ([Int]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    private let common: [[Int]] = [[5,5,5,5,5], [8,8,8], [10,10,10], [12,12,12], [8,8,8,8], [3,3,3,3,3]]

    var body: some View {
        NavigationStack {
            List {
                Section("Common") {
                    ForEach(common, id: \.self) { reps in
                        Button("\(reps.count) sets · \(reps.map(String.init).joined(separator: "-")) reps") {
                            onSelect(reps); dismiss()
                        }
                    }
                }
                Section("Custom") {
                    TextField("Example: 12, 10, 8", text: $custom)
                        .keyboardType(.numbersAndPunctuation)
                    Button("Use custom structure") {
                        let reps = custom.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                        if !reps.isEmpty { onSelect(reps); dismiss() }
                    }
                    .disabled(custom.isEmpty)
                }
            }
            .navigationTitle("Rep structure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { custom = current.map(String.init).joined(separator: ", ") }
        }
    }
}
