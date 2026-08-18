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

    private func compactSetLine(_ set: EditableSet) -> String {
        let weight = set.targetWeight.map { Format.weightValue($0, unit: unit) } ?? "BW"
        return "\(weight)×\(set.targetReps)"
    }
}
