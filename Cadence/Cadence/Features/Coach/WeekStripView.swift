import SwiftUI
import CadenceCore

struct WeekStripView: View {
    let plan: WeeklyPlan
    let balance: WeeklyBalance
    let preferences: CoachSchedulePreferences
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("This Week")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    ForEach(plan.currentWeekDays) { day in
                        dayCell(day)
                    }
                }

                progressLine
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: .green)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.weekStrip")
        .accessibilityLabel(weekStripAccessibilityLabel)
    }

    @ViewBuilder
    private func dayCell(_ day: WeeklyPlan.DayOutline) -> some View {
        let initial = calendarShort(for: day.date)
        VStack(spacing: 4) {
            Text(initial)
                .font(.caption2.weight(.medium))
                .foregroundStyle(day.isToday ? .primary : .secondary)
                .frame(width: 24)
            dayGlyph(day)
                .frame(width: 24, height: 24)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background {
            if day.isToday {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.blue, lineWidth: 2)
            }
        }
        .accessibilityLabel(dayAccessibilityLabel(day))
    }

    @ViewBuilder
    private func dayGlyph(_ day: WeeklyPlan.DayOutline) -> some View {
        if day.isCompleted {
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        } else if day.isToday {
            Circle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: 22, height: 22)
                .overlay {
                    Text(calendarDay(for: day.date))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary)
                }
        } else if day.isFuture, hasSessions(day) {
            Circle()
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1.5)
                .frame(width: 22, height: 22)
        } else {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 6, height: 6)
        }
    }

    private func hasSessions(_ day: WeeklyPlan.DayOutline) -> Bool {
        day.sessions.contains { !$0.isRest || $0.kind == .rest }
    }

    @ViewBuilder
    private var progressLine: some View {
        let strengthDone = balance.strengthDays
        let strengthTarget = preferences.strengthDaysPerWeek
        let cardioDone = balance.cardioDays
        let cardioTarget = preferences.cardioDaysPerWeek
        HStack(spacing: 2) {
            Text("\(strengthDone)/\(strengthTarget) strength")
            Text("·")
            Text("\(cardioDone)/\(cardioTarget) cardio this week")
        }
    }

    private var weekStripAccessibilityLabel: String {
        let strengthDone = balance.strengthDays
        let strengthTarget = preferences.strengthDaysPerWeek
        let cardioDone = balance.cardioDays
        let cardioTarget = preferences.cardioDaysPerWeek
        let dayLabels = plan.currentWeekDays.map { dayAccessibilityLabel($0) }.joined(separator: ", ")
        return "This week: \(strengthDone) of \(strengthTarget) strength, \(cardioDone) of \(cardioTarget) cardio. \(dayLabels)"
    }

    private func calendarShort(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }

    private func calendarDay(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    private func dayAccessibilityLabel(_ day: WeeklyPlan.DayOutline) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        let name = f.string(from: day.date)
        if day.isCompleted {
            return "\(name) completed"
        } else if day.isToday {
            return "\(name) today"
        } else if day.isPast {
            return "\(name) past"
        } else {
            let sessions = day.sessions.filter { !$0.isRest || $0.kind == .rest }
            if sessions.isEmpty {
                return "\(name) rest"
            } else {
                let labels = sessions.map(\.label).joined(separator: ", ")
                return "\(name): \(labels)"
            }
        }
    }
}
