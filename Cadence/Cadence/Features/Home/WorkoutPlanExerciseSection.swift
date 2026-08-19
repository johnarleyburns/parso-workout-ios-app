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
    let onSwap: () -> Void
    let onRemove: () -> Void

    /// nil is the owner ("Me"), which is also the default selection.
    @State private var selectedPerformerID: UUID?

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
            Menu {
                Button(action: onSwap) {
                    Label("Swap Exercise", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("editor.swapExercise.\(exercise.name)")

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
            Text(loadLabel(for: set.wrappedValue))
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
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

    private var selectedPerformerName: String {
        exercise.performerPlans.first { $0.performerID == selectedPerformerID }?.name ?? "Me"
    }
}
