import SwiftUI
import CadenceCore
import CadenceFeatures

/// One planned exercise as a Home-rhythm card. Editable outside a `List`, so
/// per-set deletion is an explicit destructive button rather than a swipe
/// (field test 2026-08-18 #5).
struct WorkoutPlanExerciseSection: View {
    @Binding var exercise: EditableExercise
    let unit: MeasurementUnitPreference
    let onSwap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardHeadingSpacing)) {
            header
            VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                    setRow(binding(forSet: set.id), at: index)
                }
                Button {
                    let last = exercise.sets.last
                    exercise.sets.append(EditableSet(targetReps: last?.targetReps ?? 10,
                                                     targetWeight: last?.targetWeight))
                } label: {
                    Label("Add Set", systemImage: "plus").font(.subheadline)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("editor.addSet.\(exercise.name)")
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

    /// Identity-keyed so deleting a set never leaves a row bound to a stale index.
    private func binding(forSet id: UUID) -> Binding<EditableSet> {
        Binding(
            get: { exercise.sets.first { $0.id == id } ?? EditableSet(targetReps: 10, targetWeight: nil) },
            set: { newValue in
                guard let i = exercise.sets.firstIndex(where: { $0.id == id }) else { return }
                exercise.sets[i] = newValue
            })
    }

    private func setRow(_ set: Binding<EditableSet>, at index: Int) -> some View {
        HStack {
            Stepper("Reps: \(set.wrappedValue.targetReps)", value: set.targetReps, in: 1...100)
                .frame(maxWidth: .infinity)
            if let w = set.wrappedValue.targetWeight {
                Text(Format.weight(w, unit: unit))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            Button(role: .destructive) {
                let id = set.wrappedValue.id
                exercise.sets.removeAll { $0.id == id }
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(exercise.sets.count <= 1)
            .accessibilityIdentifier("editor.removeSet.\(exercise.name).\(index)")
            .accessibilityLabel("Remove set \(index + 1)")
        }
    }
}
