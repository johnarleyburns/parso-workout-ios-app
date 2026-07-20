import SwiftUI
import CadenceCore
import CadenceFeatures

/// Extracted "What you did" entry row from `HomeView` to keep it
/// under the test-pyramid ratchet ceiling.
struct HomeWhatYouDidRow: View {
    let entry: TodayActivityPresenter.Entry
    let target: WhatYouDidTarget?
    let onOpen: (WhatYouDidTarget) -> Void

    enum WhatYouDidTarget { case strength(WorkoutSession), cardio(CardioWorkout) }

    var body: some View {
        let hasDestination = target != nil
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
            if hasDestination {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())

        Group {
            if hasDestination, let t = target {
                Button { Haptics.selection(); onOpen(t) } label: { rowContent }
                    .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.fact.\(entry.id)")
    }
}
