import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct YourWeekView: View {
    let decision: CoachDecision
    let facts: CoachFacts
    var sessions: [WorkoutSession] = []
    var cardio: [CardioWorkout] = []
    @Binding var path: NavigationPath
    @Environment(AppSettings.self) private var settingsObject

    init(decision: CoachDecision, facts: CoachFacts,
         sessions: [WorkoutSession] = [], cardio: [CardioWorkout] = [],
         path: Binding<NavigationPath> = .constant(NavigationPath())) {
        self.decision = decision
        self.facts = facts
        self.sessions = sessions
        self.cardio = cardio
        self._path = path
    }

    var body: some View {
        @Bindable var settings = settingsObject
        let effectivePrefs = settings.coachSchedulePreferences
        let balance = decision.weeklyBalance
        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: effectivePrefs)
        let completed = plan.completedDaysInGeneratedWeek
        let nextWeek = plan.nextWeekDays.filter { !$0.sessions.isEmpty }
        let stepSummary = facts.stepSummary ?? StepActivitySummary(from: [])
        let stepTarget = effectivePrefs.dailyStepTarget
        let strengthToGo = max(0, effectivePrefs.strengthDaysPerWeek - balance.strengthDays)
        let cardioToGo = max(0, effectivePrefs.cardioDaysPerWeek - balance.cardioDays)
        let minutesToGo = max(0, 150 - Int(balance.moderateEquivalentMinutes))
        let stepsToGo = max(0, stepTarget - Int(stepSummary.sevenDayAverageSteps))

        let weekStart = WeeklyStats.weekStart(now: Date())
        let tonnageKg = WeeklyStats.volumeKg(sessions, since: weekStart)
        let zoneMinutes = YourWeekPresenter.weeklyZoneMinutes(cardio: cardio, since: weekStart, age: settingsObject.userAge)

        List {
            Section("This Week") {
                ForEach(plan.currentWeekDays) { day in
                    dayRow(day)
                }
            }

            Section("This Week So Far") {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "dumbbell.fill").foregroundStyle(.green)
                        Text("Strength days").font(.subheadline)
                        Spacer()
                        Text("\(balance.strengthDays)")
                            .font(.subheadline.bold()).monospacedDigit()
                            + Text(strengthToGo > 0 ? "  \(strengthToGo) to go · target \(effectivePrefs.strengthDaysPerWeek)+" : "  target met").font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, Double(balance.strengthDays) / Double(effectivePrefs.strengthDaysPerWeek)))
                        .tint(.green)

                    // Strength tonnage this week (issue 7).
                    HStack {
                        Image(systemName: "scalemass.fill").foregroundStyle(.green)
                        Text("Strength tonnage").font(.subheadline)
                        Spacer()
                        Text(WorkoutMath.tonnageLabel(volumeKg: tonnageKg, unit: settings.unit))
                            .font(.subheadline.bold()).monospacedDigit()
                            .accessibilityIdentifier("yourPlan.tonnage")
                    }

                    HStack {
                        Image(systemName: "heart.fill").foregroundStyle(.teal)
                        Text("Cardio days").font(.subheadline)
                        Spacer()
                        Text("\(balance.cardioDays)")
                            .font(.subheadline.bold()).monospacedDigit()
                            + Text(cardioToGo > 0 ? "  \(cardioToGo) to go · target \(effectivePrefs.cardioDaysPerWeek)" : "  target met").font(.caption).foregroundStyle(.secondary)
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
                            + Text(minutesToGo > 0 ? "  \(minutesToGo) min to go · floor 150" : "  target met").font(.caption).foregroundStyle(.secondary)
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
                            + Text(stepsToGo > 0 ? "  \(stepsToGo)/day to go · target \(stepTarget)" : "  on target").font(.caption).foregroundStyle(.secondary)
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

            // Cardio HR-zone breakdown this week (issue 7). A stacked colored bar
            // (Z1→Z5, cool→warm) segments the total weekly minutes by zone, with a
            // per-zone minute legend beneath it.
            if !zoneMinutes.isEmpty {
                Section("Cardio HR zones (this week)") {
                    ZoneBar(minutes: zoneMinutes)
                        .accessibilityIdentifier("yourPlan.zoneBar")
                    ForEach(YourWeekPresenter.zoneRows(zoneMinutes), id: \.zone) { row in
                        HStack {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Self.zoneColor(row.zone))
                                .frame(width: 12, height: 12)
                                .accessibilityHidden(true)
                            Text("Z\(row.zone)").font(.subheadline.bold()).monospacedDigit()
                                .frame(width: 32, alignment: .leading)
                            Text(CardioMath.zoneName(row.zone)).font(.subheadline)
                            Spacer()
                            Text("\(Int(row.minutes.rounded())) min")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("yourPlan.zone.\(row.zone)")
                    }
                    if settings.userAge == nil {
                        Text("Estimated from workout type — add your age in onboarding or Coach preferences for HR-based zones.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let citation = CitationRegistry.citation(forId: "seilerPolarized2010") {
                        CitationLink(citation: citation, compact: true)
                    }
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

            Section {
                NavigationLink {
                    CoachSchedulePreferencesView()
                } label: {
                    Label("Coach preferences", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settings.coach.schedulePreferences")
            } header: {
                Text("Plan")
            } footer: {
                Text("Goal, experience, schedule, and step target are in Coach preferences.")
            }
        }
        .navigationTitle("Your Plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A day row that is tappable when it maps to a real logged workout (completed
    /// day → its summary) or a future planned day (read-only preview).
    @ViewBuilder
    private func dayRow(_ day: WeeklyPlan.DayOutline) -> some View {
        if day.isPast, day.isCompleted, let route = completedRoute(for: day) {
            Button {
                path.append(route)
            } label: {
                HStack {
                    CoachPlanDayRow(day: day)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("yourPlan.day.\(day.id)")
        } else if day.isFuture, !day.sessions.isEmpty {
            NavigationLink {
                PlannedDayPreviewView(day: day, goal: facts.goal)
            } label: {
                CoachPlanDayRow(day: day)
            }
            .accessibilityIdentifier("yourPlan.day.\(day.id)")
        } else {
            CoachPlanDayRow(day: day)
        }
    }

    /// Maps a completed day to the first real workout logged that day, preferring
    /// strength, so tapping opens its history summary.
    private func completedRoute(for day: WeeklyPlan.DayOutline) -> HistorySummaryRoute? {
        let cal = Calendar.current
        if let s = sessions.first(where: { cal.isDate($0.date, inSameDayAs: day.date) && !$0.orderedSets.isEmpty }) {
            return .strength(s)
        }
        if let c = cardio.first(where: { cal.isDate($0.start, inSameDayAs: day.date) }) {
            return .cardio(c)
        }
        return nil
    }

    /// Zone color scale Z1→Z5 (cool→warm), matching the HR-zone intensity ramp.
    static func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return .blue
        case 2: return .green
        case 3: return .yellow
        case 4: return .orange
        default: return .red
        }
    }

    /// A horizontal stacked bar segmenting the total weekly cardio minutes by zone
    /// (Z1..Z5), each segment proportional to its share. VoiceOver reads each zone's
    /// minutes and % (NFR-2). Dynamic Type unaffected — the bar is a fixed-height rail.
    private struct ZoneBar: View {
        let minutes: [Int: Double]

        private var segments: [(zone: Int, minutes: Double)] {
            (1...5).compactMap { z in
                guard let m = minutes[z], m > 0.5 else { return nil }
                return (z, m)
            }
        }
        private var total: Double { segments.reduce(0) { $0 + $1.minutes } }

        var body: some View {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(segments, id: \.zone) { seg in
                        YourWeekView.zoneColor(seg.zone)
                            .frame(width: total > 0 ? geo.size.width * (seg.minutes / total) : 0)
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly cardio heart-rate zone distribution")
            .accessibilityValue(accessibilitySummary)
        }

        private var accessibilitySummary: String {
            guard total > 0 else { return "No cardio this week" }
            return segments.map { seg in
                let pct = Int((seg.minutes / total * 100).rounded())
                return "Zone \(seg.zone), \(CardioMath.zoneName(seg.zone)): \(Int(seg.minutes.rounded())) minutes, \(pct) percent"
            }.joined(separator: ". ")
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
                Text(weekdayLabel(for: day.date)).font(.caption.weight(.semibold)).lineLimit(1).frame(width: 44, alignment: .leading)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background {
                        if day.isToday {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.blue, lineWidth: 2)
                        }
                    }
                if day.isPast {
                    if day.isCompleted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(day.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
                    } else {
                        Text(day.label)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                    }
                } else {
                    if day.sessions.isEmpty {
                        Text(day.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                    } else {
                        ForEach(day.sessions) { session in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(session.isHard ? Color.green : session.kind == .recovery || session.kind == .rest ? Color.gray.opacity(0.3) : Color.teal)
                                    .frame(width: 8, height: 8)
                                Text(session.label).font(.subheadline)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    private func weekdayLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}
