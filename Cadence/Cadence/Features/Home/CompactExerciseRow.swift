import SwiftUI
import CadenceCore
import CadenceFeatures

struct CompactExerciseRow: View {
    let exercise: EditableExercise
    let unit: MeasurementUnitPreference

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardHeadingSpacing)) {
            Text(exercise.name).font(.headline)
            if performerPlans.isEmpty {
                Text(ownerLine)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
                    ForEach(performerPlans) { plan in
                        performerRow(plan)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("editor.compactExercise.\(exercise.name)")
        .accessibilityValue(accessibilityValue)
    }

    /// One line per performer, `Me` first (field test 2026-08-18 #4). A solo plan
    /// keeps the single unlabelled line it has always had.
    private func performerRow(_ plan: EditablePerformerPlan) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(plan.name)
                .font(.subheadline.weight(plan.isMe ? .semibold : .regular))
                .frame(width: 64, alignment: .leading)
            Text(PlanFormatting.setsLine(plan.sets, isBodyweight: isBodyweight, unit: unit))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("editor.exercisePerformer.\(exercise.name).\(plan.name)")
    }

    private var performerPlans: [EditablePerformerPlan] {
        PlanFormatting.orderedPerformerPlans(exercise)
    }

    /// `BW` is a statement about the movement, not about missing data: a loaded
    /// lift with no resolvable history renders an em dash rather than claiming it
    /// is a bodyweight exercise (field test 2026-08-18 #2, decision D4).
    private var isBodyweight: Bool { ExerciseLoading.isBodyweight(named: exercise.name) }

    private var ownerLine: String {
        PlanFormatting.setsLine(exercise.sets, isBodyweight: isBodyweight, unit: unit)
    }

    private var accessibilityValue: String {
        guard !performerPlans.isEmpty else {
            return PlanFormatting.setsLine(exercise.sets, isBodyweight: isBodyweight,
                                           unit: unit, separator: ", ")
        }
        return performerPlans.map {
            "\($0.name): \(PlanFormatting.setsLine($0.sets, isBodyweight: isBodyweight, unit: unit, separator: ", "))"
        }
        .joined(separator: ". ")
    }
}
