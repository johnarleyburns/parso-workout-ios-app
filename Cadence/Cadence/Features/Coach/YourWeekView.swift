import SwiftUI
import CadenceCore

struct YourWeekView: View {
    let decision: CoachDecision
    let facts: CoachFacts

    var body: some View {
        let balance = decision.weeklyBalance
        let plan = WeeklyPlan.generate(from: facts)
        let completed = plan.completedDaysInGeneratedWeek
        let remaining = plan.remainingCalendarWeekDays.filter { $0.sessionKind != nil }
        List {
            Section("This Week So Far") {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "dumbbell.fill").foregroundStyle(.green)
                        Text("Strength days").font(.subheadline)
                        Spacer()
                        Text("\(balance.strengthDays)")
                            .font(.subheadline.bold()).monospacedDigit()
                            + Text("  (target: 2+)").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, Double(balance.strengthDays) / 2))
                        .tint(.green)

                    HStack {
                        Image(systemName: "heart.fill").foregroundStyle(.teal)
                        Text("Aerobic minutes").font(.subheadline)
                        Spacer()
                        Text("\(Int(balance.moderateEquivalentMinutes))")
                            .font(.subheadline.bold()).monospacedDigit()
                            + Text("  (target: 150)").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, balance.moderateEquivalentMinutes / 150))
                        .tint(.teal)

                    HStack {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                        Text("Hard days").font(.subheadline)
                        Spacer()
                        Text("\(balance.hardDays)").font(.subheadline.bold()).monospacedDigit()
                    }

                    HStack {
                        Image(systemName: "arrow.trianglehead.clockwise").foregroundStyle(.red)
                        Text("Consecutive hard").font(.subheadline)
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
                        HStack {
                            Text(weekdayLabel(for: day.date)).font(.caption).frame(width: 32, alignment: .leading)
                            Circle()
                                .fill(day.isHard ? Color.green : day.sessionKind != nil ? Color.teal : Color.gray.opacity(0.3))
                                .frame(width: 10, height: 10)
                            Text(day.sessionKind != nil ? day.label : "—")
                                .font(.subheadline)
                            Spacer()
                            if let kind = day.sessionKind {
                                Text(kindLabel(kind)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                Section("Planned (rest of week)") {
                    Text("No more planned sessions this week.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("7-day history") {
                ForEach(plan.historyDays) { day in
                    HStack {
                        Text(weekdayLabel(for: day.date)).font(.caption).frame(width: 32, alignment: .leading)
                        Circle()
                            .fill(day.isCompleted ? (day.isHard ? Color.green : Color.teal) : Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                        Text(day.isCompleted ? day.label : "—").font(.subheadline)
                        if day.isToday { Text("Today").font(.caption.bold()).foregroundStyle(.tint) }
                        Spacer()
                        if let kind = day.sessionKind {
                            Text(kindLabel(kind)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
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

    private func kindLabel(_ kind: CoachSessionKind) -> String {
        switch kind {
        case .strength: return "Hard"
        case .easyAerobic: return "Easy"
        case .moderateAerobic: return "Cardio"
        case .vo2Intervals: return "VO₂"
        case .recovery: return "Recovery"
        case .rest: return "Rest"
        case .assessment: return "Test"
        }
    }

    private func weekdayLabel(for date: Date) -> String {
        let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let idx = Calendar.current.component(.weekday, from: date) - 2
        return idx >= 0 && idx < 7 ? weekdays[idx] : ""
    }
}
