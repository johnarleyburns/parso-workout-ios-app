import SwiftUI
import CadenceCore

struct YourWeekView: View {
    let decision: CoachDecision
    let facts: CoachFacts
    @Environment(AppSettings.self) private var settings
    @State private var showSchedulePrefs = false

    var body: some View {
        let effectivePrefs = settings.coachSchedulePreferences
        let balance = decision.weeklyBalance
        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: effectivePrefs)
        let completed = plan.completedDaysInGeneratedWeek
        let nextWeek = plan.nextWeekDays.filter { !$0.sessions.isEmpty }
        let stepSummary = facts.stepSummary ?? StepActivitySummary(from: [])
        let stepTarget = effectivePrefs.dailyStepTarget

        List {
            Section("This Week So Far") {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "dumbbell.fill").foregroundStyle(.green)
                        Text("Strength days").font(.subheadline)
                        Spacer()
                        Text("\(balance.strengthDays)")
                            .font(.subheadline.bold()).monospacedDigit()
                            + Text("  (target: \(effectivePrefs.strengthDaysPerWeek)+)").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, Double(balance.strengthDays) / Double(effectivePrefs.strengthDaysPerWeek)))
                        .tint(.green)

                    HStack {
                        Image(systemName: "heart.fill").foregroundStyle(.teal)
                        Text("Cardio days").font(.subheadline)
                        Spacer()
                        Text("\(balance.cardioDays)")
                            .font(.subheadline.bold()).monospacedDigit()
                            + Text("  (target: \(effectivePrefs.cardioDaysPerWeek))").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: effectivePrefs.cardioDaysPerWeek > 0
                        ? min(1, Double(balance.cardioDays) / Double(effectivePrefs.cardioDaysPerWeek)) : 1)
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
                        Image(systemName: "shoeprints.fill")
                            .foregroundStyle(stepsColor(stepSummary.status))
                        Text("Steps (7-day avg)").font(.subheadline)
                        Spacer()
                        Text("\(Int(stepSummary.sevenDayAverageSteps))")
                            .font(.subheadline.bold()).monospacedDigit()
                            + Text("  (target: \(stepTarget))").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, stepSummary.sevenDayAverageSteps / Double(stepTarget)))
                        .tint(stepsColor(stepSummary.status))

                    HStack(spacing: 4) {
                        Text(stepSummary.status.displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(stepsColor(stepSummary.status))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(stepsColor(stepSummary.status).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        Text("Today: \(stepSummary.todaySteps) steps").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                    }

                    if let citation = CitationRegistry.citation(forId: "saintMauriceSteps2020") {
                        CitationLink(citation: citation, compact: true)
                    }

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

            if !nextWeek.isEmpty {
                Section("Planned (next week)") {
                    ForEach(nextWeek) { day in
                        CoachPlanDayRow(day: day)
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
        .navigationTitle("Your Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSchedulePrefs = true } label: {
                    Image(systemName: "calendar.badge.clock")
                }
                .accessibilityLabel("Schedule preferences")
            }
        }
        .sheet(isPresented: $showSchedulePrefs) {
            NavigationStack {
                CoachSchedulePreferencesView()
            }
        }
    }

    private func stepsColor(_ status: StepHealthStatus) -> Color {
        switch status {
        case .low: return .orange
        case .building: return .blue
        case .onTrack: return .green
        }
    }
}

struct CoachPlanDayRow: View {
    let day: WeeklyPlan.DayOutline

    var body: some View {
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
