import SwiftUI
import CadenceCore
import CadenceFeatures

/// One exercise in a workout summary: a compact roll-up that expands **in place**
/// to a read-only, per-performer set list (field test 2026-08-18 #1, decision
/// **D7**). Tapping never navigates — `Edit` in the toolbar stays the only route
/// into the editor.
struct WorkoutSummaryExerciseRow: View {
    let line: WorkoutSummaryData.ExerciseLine
    let unit: MeasurementUnitPreference
    let isExpanded: Bool
    let idPrefix: String
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 6) {
                headline
                Text(summaryLine)
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isExpanded, !performers.isEmpty {
                    Divider()
                    ForEach(performers) { performer in
                        performerRow(performer)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            // A card is an HStack with a Spacer; without an explicit shape the
            // gap between title and chevron is not tappable.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // `.contain` must precede the identifier, or the styled card collapses
        // its children and the per-performer identifiers vanish from the tree.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(cardID)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows every set")
    }

    private var headline: some View {
        HStack {
            Text(line.name).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let top = line.topSetWeightKg {
                Text(WorkoutSummaryPresenter.topLabel(topKg: top,
                                                      bodyweight: line.usesBodyweight,
                                                      unit: unit))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func performerRow(_ performer: WorkoutSummaryData.PerformerLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(performer.name)
                .font(.caption.weight(.semibold))
                .frame(minWidth: 44, alignment: .leading)
            Text(WorkoutSummaryPresenter.performerSetsText(performer, unit: unit))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(cardID).performer.\(performer.name)")
    }

    /// Expansion state plus, when open, every performer's sets — so VoiceOver
    /// gets the detail without having to swipe through each row.
    private var accessibilityValue: String {
        guard isExpanded else { return "Collapsed" }
        let detail = WorkoutSummaryPresenter.expandedAccessibilityValue(line, unit: unit)
        return detail.isEmpty ? "Expanded" : "Expanded. \(detail)"
    }

    private var performers: [WorkoutSummaryData.PerformerLine] {
        WorkoutSummaryPresenter.orderedPerformers(line)
    }

    /// Unchanged from the pre-expansion row so existing tests and the smoke test
    /// keep resolving it.
    private var cardID: String {
        "\(idPrefix).\(line.sourceExerciseID?.uuidString ?? line.name)"
    }

    private var summaryLine: String {
        if let done = WorkoutSummaryPresenter.doneSummary(line, unit: unit) {
            return done
        }
        return "\(line.setCount) set\(line.setCount == 1 ? "" : "s") · reps "
            + line.reps.map(String.init).joined(separator: ", ")
    }
}
