import SwiftUI
import CadenceCore
import CadenceFeatures

/// Extracted workout row from the expanded Home This Week card to keep the
/// dashboard view under the test-pyramid ratchet ceiling.
struct HomeWeekWorkoutRow: View {
    let entry: TodayActivityPresenter.Entry
    let onOpen: () -> Void

    var body: some View {
        let rowContent = HStack(spacing: 8) {
            Image(systemName: entry.kind == .strength ? "dumbbell.fill" : "heart.fill")
                .font(.caption)
                .foregroundStyle(entry.kind == .strength ? .green : .teal)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                if let detail = entry.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(entry.value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())

        Button { Haptics.selection(); onOpen() } label: { rowContent }
            .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.week.workout.\(entry.id)")
    }
}
