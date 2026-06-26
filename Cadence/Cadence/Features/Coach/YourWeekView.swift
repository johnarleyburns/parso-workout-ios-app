import SwiftUI
import CadenceCore

struct YourWeekView: View {
    let decision: CoachDecision
    let facts: CoachFacts
    let preferences: CoachSchedulePreferences

    var body: some View {
        let balance = decision.weeklyBalance
        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: preferences)
        let completed = plan.completedDaysInGeneratedWeek
        let remaining = plan.remainingCalendarWeekDays.filter { !$0.sessions.isEmpty }
        let nextWeek = plan.nextWeekDays.filter { !$0.sessions.isEmpty }
        List {
            Section("This Week So Far") {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "dumbbell.fill").foregroundStyle(.green)
                        Text("Strength days").font(.subheadline)
                        Spacer()
                        Text("\(balance.strengthDays)")
                            .font(.subheadline.bold()).monospacedDigit()
                            + Text("  (target: \(preferences.strengthDaysPerWeek)+)").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, Double(balance.strengthDays) / Double(preferences.strengthDaysPerWeek)))
                        .tint(.green)

                    HStack {
                        Image(systemName: "heart.fill").foregroundStyle(.teal)
                        Text("Cardio days").font(.subheadline)
                        Spacer()
                        Text("\(balance.cardioDays)")
                            .font(.subheadline.bold()).monospacedDigit()
                            + Text("  (target: \(preferences.cardioDaysPerWeek))").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: preferences.cardioDaysPerWeek > 0
                        ? min(1, Double(balance.cardioDays) / Double(preferences.cardioDaysPerWeek)) : 1)
                        .tint(.teal)

                    HStack {
                        Image(systemName: "timer").foregroundStyle(.blue)
                        Text("Mod-equivalent minutes").font(.subheadline)
                        Spacer()
                        Text("\(Int(balance.moderateEquivalentMinutes))")
                            .font(.subheadline.bold()).monospacedDigit()
                            + Text("  (health floor: 150)").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, balance.moderateEquivalentMinutes / 150))
                        .tint(.blue)

                    HStack {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                        Text("Consecutive hard days").font(.subheadline)
                        Spacer()
                        Text("\(balance.consecutiveHardDays)").font(.subheadline.bold()).monospacedDigit()
                    }
                }
                .padding(.vertical, 4)

                if completed.count > 0 {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(completed.count) day\(completed.count == 1 ? "" : "s") completed").font(.caption)
                    }
                }
            }

            if !remaining.isEmpty {
                Section("Planned (rest of week)") {
                    ForEach(remaining) { day in
                        dayRow(day)
                    }
                }
            } else {
                Section("Planned (rest of week)") {
                    Text("No more planned sessions this week.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if !nextWeek.isEmpty {
                Section("Planned (next week)") {
                    ForEach(nextWeek) { day in
                        dayRow(day)
                    }
                }
            }

            if let vo2 = balance.vo2maxLatest {
                Section("VO₂max") {
                    HStack {
                        Text(String(format: "%.1f", vo2)).font(.title.bold()).foregroundStyle(.teal)
                        VStack(alignment: .leading) {
                            Text(balance.vo2maxProtocol ?? "Field test").font(.caption)
                            if let trend = balance.vo2maxTrend {
                                Text(trend == .rising ? "Improving" : trend == .declining ? "Declining" : "Stable")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Your week")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func dayRow(_ day: WeeklyPlan.DayOutline) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(weekdayLabel(for: day.date)).font(.caption.weight(.semibold)).frame(width: 32, alignment: .leading)
                ForEach(day.sessions) { session in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(session.isHard ? Color.green : session.kind == .recovery || session.kind == .rest ? Color.gray.opacity(0.3) : Color.teal)
                            .frame(width: 8, height: 8)
                        Text(session.label).font(.subheadline)
                        if let note = session.timingNote {
                            Text(note).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
                }
                if day.isToday { Text("Today").font(.caption.bold()).foregroundStyle(.tint) }
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }

    private func weekdayLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}
