import SwiftUI
import SwiftData
import CadenceCore

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
        let zoneMinutes = weeklyZoneMinutes(since: weekStart)

        List {
            // TODAY-first (issue 7): today's planned-or-completed work up top.
            if let today = plan.today {
                Section("Today") {
                    TodayPlanRow(day: today)
                        .accessibilityIdentifier("yourPlan.today")
                }
            }

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

            // Cardio HR-zone breakdown this week (issue 7).
            if !zoneMinutes.isEmpty {
                Section("Cardio HR zones (this week)") {
                    ForEach(zoneRows(zoneMinutes), id: \.zone) { row in
                        HStack {
                            Text("Z\(row.zone)").font(.subheadline.bold()).monospacedDigit()
                                .frame(width: 32, alignment: .leading)
                            Text(CardioMath.zoneName(row.zone)).font(.subheadline)
                            Spacer()
                            Text("\(Int(row.minutes.rounded())) min")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("yourPlan.zone.\(row.zone)")
                    }
                    if settings.userAge == nil {
                        Text("Estimated from workout type — add your age in onboarding or Coach preferences for HR-based zones.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let citation = CitationRegistry.citation(forId: "tanakaMaxHR2001") {
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

    private struct ZoneRow { let zone: Int; let minutes: Double }

    private func zoneRows(_ minutes: [Int: Double]) -> [ZoneRow] {
        (1...5).compactMap { z in
            guard let m = minutes[z], m > 0.5 else { return nil }
            return ZoneRow(zone: z, minutes: m)
        }
    }

    private func weeklyZoneMinutes(since: Date) -> [Int: Double] {
        let weekCardio = cardio.filter { $0.start >= since }
        let sessionsForZones: [CardioZoneAggregator.Session] = weekCardio.map { c in
            CardioZoneAggregator.Session(
                modality: modality(for: c.typeValue),
                intensity: intensity(for: c),
                durationMinutes: c.duration / 60,
                hrSamples: (c.hrSamples ?? []).map { CardioZoneAggregator.HRPoint(t: $0.t, bpm: $0.bpm) })
        }
        return CardioZoneAggregator.weeklyZoneMinutes(sessions: sessionsForZones, age: settingsObject.userAge)
    }

    private func modality(for type: CardioType) -> CoachSession.AerobicModality {
        switch type {
        case .walk: return .walk
        case .run: return .run
        case .cycle: return .cycle
        case .swim: return .swim
        case .rowing: return .row
        case .boxing: return .boxing
        default: return .other
        }
    }

    private func intensity(for c: CardioWorkout) -> CoachSession.AerobicIntensity {
        // Rough classification from average HR against an age-based HRmax when
        // present; else infer from modality (boxing/run lean harder than walk).
        if let avg = c.avgHeartRate, avg > 0 {
            let maxHR = CardioMath.defaultMaxHR(age: settingsObject.userAge)
            let pct = avg / maxHR
            if pct >= 0.80 { return .vigorous }
            if pct >= 0.65 { return .moderate }
            return .easy
        }
        switch c.typeValue {
        case .boxing: return .vigorous
        case .run, .rowing: return .moderate
        default: return .easy
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

/// TODAY's planned-or-completed work, shown with a little more detail than a row.
private struct TodayPlanRow: View {
    let day: WeeklyPlan.DayOutline

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if day.isCompleted {
                Label("Today's plan is complete", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            if day.sessions.isEmpty {
                Text(day.label).font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(day.sessions) { session in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(session.isHard ? Color.green : session.kind == .recovery || session.kind == .rest ? Color.gray.opacity(0.3) : Color.teal)
                            .frame(width: 8, height: 8)
                        Text(session.label).font(.subheadline)
                        if let note = session.timingNote {
                            Text(note).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct CoachPlanDayRow: View {
    let day: WeeklyPlan.DayOutline

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(weekdayLabel(for: day.date)).font(.caption.weight(.semibold)).frame(width: 32, alignment: .leading)
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
                }
                if day.isToday { Text("Today").font(.caption.bold()).foregroundStyle(.tint) }
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
