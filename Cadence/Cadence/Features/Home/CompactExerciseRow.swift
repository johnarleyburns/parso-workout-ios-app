import SwiftUI
import CadenceCore
import CadenceFeatures

struct CompactExerciseRow: View {
    let exercise: EditableExercise
    let unit: MeasurementUnitPreference

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardHeadingSpacing)) {
            Text(exercise.name).font(.headline)
            Text(exercise.sets.map(compactSetLine).joined(separator: "  ·  "))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("editor.compactExercise.\(exercise.name)")
        .accessibilityValue(exercise.sets.map(compactSetLine).joined(separator: ", "))
    }

    /// `BW` is a statement about the movement, not about missing data: a loaded
    /// lift with no resolvable history renders an em dash rather than claiming it
    /// is a bodyweight exercise (field test 2026-08-18 #2, decision D4).
    private var isBodyweight: Bool { ExerciseLoading.isBodyweight(named: exercise.name) }

    private func compactSetLine(_ set: EditableSet) -> String {
        if let w = set.targetWeight { return "\(Format.weightValue(w, unit: unit))×\(set.targetReps)" }
        return isBodyweight ? "BW×\(set.targetReps)" : "—×\(set.targetReps)"
    }
}
