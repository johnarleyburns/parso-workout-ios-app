import SwiftUI
import CadenceCore

/// One row of the Your Plan week list: the weekday tag plus one chip per session
/// (coach-user-control Phase 4 — a strength AM + boxing PM day shows both).
struct CoachPlanDayRow: View {
    let day: WeeklyPlan.DayOutline

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(weekdayLabel(for: day.date)).font(.caption.weight(.semibold)).lineLimit(1).frame(width: 44, alignment: .leading)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background {
                        if day.isToday {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.blue, lineWidth: 2)
                        }
                    }
                FlowLayout(spacing: 6) {
                    if day.isPast {
                        if day.isCompleted {
                            if day.sessions.isEmpty {
                                completedChip(label: day.label)
                            } else {
                                ForEach(day.sessions) { session in
                                    completedChip(label: session.label)
                                }
                            }
                        } else {
                            Text(day.label)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    } else {
                        if day.sessions.isEmpty {
                            Text(day.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .fixedSize(horizontal: true, vertical: false)
                        } else {
                            ForEach(day.sessions) { session in
                                plannedChip(session)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    private func completedChip(label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
    }

    private func plannedChip(_ session: PlannedSession) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(session.isHard ? Color.green : session.kind == .recovery || session.kind == .rest ? Color.gray.opacity(0.3) : Color.teal)
                .frame(width: 8, height: 8)
            Text(session.label)
                .font(.subheadline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
    }

    private func weekdayLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}
