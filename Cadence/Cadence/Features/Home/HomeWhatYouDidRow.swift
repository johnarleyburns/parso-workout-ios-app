import SwiftUI
import CadenceCore
import CadenceFeatures

/// The shared "one workout, one line" row. This Week renders its completed
/// entries with it, and Workouts Today renders its completed rows with it too
/// (field test 2026-08-18 #6 asked for "just like on This Week"), so there is
/// exactly one implementation of that line.
struct HomeWeekWorkoutRow: View {
    struct Content {
        let isStrength: Bool
        let title: String
        let detail: String?
        let value: String
        /// Trailing status badge — `COMPLETED`. Nil in This Week, which needs no
        /// badge because everything in it is completed by construction.
        let badge: String?
        let identifier: String
    }

    let content: Content
    let onOpen: () -> Void

    init(entry: TodayActivityPresenter.Entry, onOpen: @escaping () -> Void) {
        self.content = Content(isStrength: entry.kind == .strength,
                               title: entry.title,
                               detail: entry.detail,
                               value: entry.value,
                               badge: nil,
                               identifier: "home.week.workout.\(entry.id)")
        self.onOpen = onOpen
    }

    init(row: WorkoutsTodayPresenter.Row, onOpen: @escaping () -> Void) {
        self.content = Content(isStrength: row.modality == .strength,
                               title: row.title,
                               detail: row.subtitle,
                               value: row.value,
                               badge: row.status.badgeText,
                               identifier: "home.today.row.\(row.sourceKey)")
        self.onOpen = onOpen
    }

    var body: some View {
        let rowContent = HStack(spacing: 8) {
            Image(systemName: content.isStrength ? "dumbbell.fill" : "heart.fill")
                .font(.caption)
                .foregroundStyle(content.isStrength ? .green : .teal)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(content.title)
                    .font(.subheadline.weight(.medium))
                if let detail = content.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if let badge = content.badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                }
                Text(content.value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())

        Button { Haptics.selection(); onOpen() } label: { rowContent }
            .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(content.identifier)
    }
}
