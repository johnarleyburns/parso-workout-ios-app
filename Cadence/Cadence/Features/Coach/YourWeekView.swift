import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct YourWeekView: View {
    let decision: CoachDecision
    let facts: CoachFacts
    let trainingFacts: TrainingFacts
    let optimizedPlan: OptimizedCoachPlan
    let plan: WeeklyPlan
    var sessions: [WorkoutSession] = []
    var cardio: [CardioWorkout] = []
    @Binding var path: NavigationPath
    @Environment(AppSettings.self) private var settingsObject
    @State private var dayChooser: DayRouteChoices?

    /// A completed day with multiple logged workouts: the chooser offering one
    /// destination per workout (coach-user-control Phase 4).
    private struct DayRouteChoices: Identifiable {
        let day: WeeklyPlan.DayOutline
        let choices: [(label: String, route: HistorySummaryRoute)]
        var id: String { day.id }
    }

    init(decision: CoachDecision, facts: CoachFacts,
         trainingFacts: TrainingFacts, optimizedPlan: OptimizedCoachPlan,
         plan: WeeklyPlan,
         sessions: [WorkoutSession] = [], cardio: [CardioWorkout] = [],
         path: Binding<NavigationPath> = .constant(NavigationPath())) {
        self.decision = decision
        self.facts = facts
        self.trainingFacts = trainingFacts
        self.optimizedPlan = optimizedPlan
        self.plan = plan
        self.sessions = sessions
        self.cardio = cardio
        self._path = path
    }

    var body: some View {
        @Bindable var settings = settingsObject
        let effectivePrefs = settings.coachSchedulePreferences
        let balance = decision.weeklyBalance
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

            // MARK: Body-part volume vs plan (§1)
            let volumeRows = WeekVolumePresenter.rows(facts: trainingFacts, optimized: optimizedPlan)
            let volumeSummary = WeekVolumePresenter.summary(rows: volumeRows)
            if !volumeRows.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        // D4 aggregate header: "Sets this week"
                        HStack {
                            Text("Sets this week").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(Format.sets(volumeSummary.doneSets)) done + \(Format.sets(volumeSummary.plannedSets)) planned")
                                .font(.subheadline.bold()).monospacedDigit()
                        }
                        HStack(spacing: 0) {
                            Text("of ~\(Int(volumeSummary.recommendedSets.rounded())) recommended")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        // Aggregate bar
                        let maxScale = max(1, volumeRows.map { max($0.barFractionDone + $0.barFractionPlanned, $0.mevTickFraction) }.max() ?? 1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(Color(.systemGray5)).frame(height: 8)
                                let totalDoneFrac = min(1, maxScale > 0 ? volumeSummary.doneSets / (volumeSummary.recommendedSets * 1.2) : 0)
                                RoundedRectangle(cornerRadius: 3).fill(Color.green)
                                    .frame(width: max(0, geo.size.width * totalDoneFrac), height: 8)
                            }
                        }
                        .frame(height: 8)

                        Divider()

                        ForEach(volumeRows) { row in
                            partVolumeRow(row)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Body-part volume vs plan")
                } footer: {
                    if let citation = CitationRegistry.citation(forId: "volumeDoseResponse") {
                        CitationLink(citation: citation, compact: true)
                    }
                }
                .accessibilityIdentifier("yourPlan.partVolume")
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
        .confirmationDialog("Open workout",
                            isPresented: Binding(get: { dayChooser != nil },
                                                 set: { if !$0 { dayChooser = nil } }),
                            titleVisibility: .visible) {
            if let chooser = dayChooser {
                ForEach(Array(chooser.choices.enumerated()), id: \.offset) { _, choice in
                    Button(choice.label) {
                        path.append(choice.route)
                        dayChooser = nil
                    }
                }
            }
        } message: {
            Text("This day has more than one logged workout.")
        }
    }

    /// A day row that is tappable when it maps to real logged workouts (completed
    /// day → its summary; multiple workouts → a chooser) or a planned day —
    /// today included — which opens the read-only preview.
    @ViewBuilder
    private func dayRow(_ day: WeeklyPlan.DayOutline) -> some View {
        let routes = completedRoutes(for: day)
        if day.isCompleted, !routes.isEmpty {
            Button {
                if routes.count == 1 {
                    path.append(routes[0].route)
                } else {
                    dayChooser = DayRouteChoices(day: day, choices: routes)
                }
            } label: {
                HStack {
                    CoachPlanDayRow(day: day)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("yourPlan.day.\(day.id)")
        } else if day.isFuture || day.isToday, !day.sessions.isEmpty {
            NavigationLink {
                PlannedDayPreviewView(
                    day: day,
                    goal: facts.goal,
                    desiredSetsPerExercise: settingsObject.coachSchedulePreferences.desiredSetsPerExercise
                )
            } label: {
                CoachPlanDayRow(day: day)
            }
            .accessibilityIdentifier("yourPlan.day.\(day.id)")
        } else {
            CoachPlanDayRow(day: day)
        }
    }

    /// Maps a completed day to every real workout logged that day — one route per
    /// session chip (coach-user-control Phase 4), matched by `sourceWorkoutId` with
    /// a same-day fallback for sessions predating the id linkage.
    private func completedRoutes(for day: WeeklyPlan.DayOutline) -> [(label: String, route: HistorySummaryRoute)] {
        var routes: [(label: String, route: HistorySummaryRoute)] = []
        for planned in day.sessions {
            guard let workoutId = planned.sourceWorkoutId else { continue }
            if let s = sessions.first(where: { $0.id == workoutId && !$0.orderedSets.isEmpty }) {
                routes.append((planned.label, .strength(s)))
            } else if let c = cardio.first(where: { $0.id == workoutId }) {
                routes.append((planned.label, .cardio(c)))
            }
        }
        if routes.isEmpty {
            let cal = Calendar.current
            if let s = sessions.first(where: { cal.isDate($0.date, inSameDayAs: day.date) && !$0.orderedSets.isEmpty }) {
                routes.append(("Strength", .strength(s)))
            } else if let c = cardio.first(where: { cal.isDate($0.start, inSameDayAs: day.date) }) {
                routes.append((c.typeValue.displayName, .cardio(c)))
            }
        }
        return routes
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

    @ViewBuilder
    private func partVolumeRow(_ row: WeekVolumePresenter.PartRow) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(row.part.displayName).font(.subheadline)
                    .accessibilityHidden(true)
                Spacer()
                Group {
                    if row.plannedSets > 0 {
                        Text("\(Format.sets(row.doneSets)) done + \(Format.sets(row.plannedSets)) planned")
                    } else {
                        Text("\(Format.sets(row.doneSets)) done")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityHidden(true)

                statusChip(row.status)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("yourPlan.partVolume.\(row.part.rawValue)")
            .accessibilityLabel(accessibilityLabel(for: row))

            // Bar: scale to MAV, solid = done, hatched = planned, tick at MEV
            let mav = row.band.upperBound
            let scale = mav > 0 ? mav : 1
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Rail
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)

                    // Done segment
                    if row.barFractionDone > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(for: row.status))
                            .frame(width: max(0, geo.size.width * min(1, row.barFractionDone)), height: 6)
                    }

                    // Planned segment (hatched)
                    if row.barFractionPlanned > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(for: row.status).opacity(0.5))
                            .frame(width: max(0, geo.size.width * min(1, row.barFractionPlanned)), height: 6)
                            .offset(x: max(0, geo.size.width * row.barFractionDone))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: max(0, geo.size.width * min(1, row.barFractionPlanned)), height: 6)
                                    .offset(x: max(0, geo.size.width * row.barFractionDone))
                                    .mask(hatchPattern)
                            }
                    }

                    // MEV tick
                    if row.mevTickFraction > 0 && row.mevTickFraction < 1 {
                        Rectangle()
                            .fill(Color(.systemGray2))
                            .frame(width: 1.5, height: 10)
                            .offset(x: max(0, geo.size.width * row.mevTickFraction) - 0.75)
                    }
                }
            }
            .frame(height: 10)

            // Band label
            HStack {
                Spacer()
                Text("\(Int(row.band.lowerBound.rounded()))–\(Int(row.band.upperBound.rounded())) rec.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusChip(_ status: WeekVolumePresenter.PartRow.Status) -> some View {
        Group {
            switch status {
            case .targetMet:
                Text("✓ target met")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            case .onTrack:
                Text("✓ on track")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.teal)
            case .short(let toGo):
                Text("⚠ \(Int(toGo.rounded())) to go")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            case .high:
                Text("↑ high")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(chipBackground(for: status), in: RoundedRectangle(cornerRadius: 5))
    }

    private func barColor(for status: WeekVolumePresenter.PartRow.Status) -> Color {
        switch status {
        case .targetMet, .onTrack: return .green
        case .short: return .orange
        case .high: return .gray
        }
    }

    private func chipBackground(for status: WeekVolumePresenter.PartRow.Status) -> Color {
        switch status {
        case .targetMet: return .green.opacity(0.14)
        case .onTrack: return .teal.opacity(0.14)
        case .short: return .orange.opacity(0.16)
        case .high: return Color(.systemGray5)
        }
    }

    private var hatchPattern: some View {
        Canvas { context, size in
            let stride: CGFloat = 4
            var x: CGFloat = 0
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x - size.height, y: size.height))
                path.addLine(to: CGPoint(x: x - size.height + 2, y: size.height))
                path.addLine(to: CGPoint(x: x + 2, y: 0))
                path.closeSubpath()
                context.fill(path, with: .color(.white.opacity(0.35)))
                x += stride
            }
        }
    }

    private func accessibilityLabel(for row: WeekVolumePresenter.PartRow) -> String {
        let statusText: String
        switch row.status {
        case .targetMet: statusText = "target met"
        case .onTrack: statusText = "on track"
        case .short(let toGo): statusText = "\(Int(toGo.rounded())) sets to go"
        case .high: statusText = "above maximum recommended"
        }
        return "\(row.part.displayName): \(Format.sets(row.doneSets)) sets done, \(Format.sets(row.plannedSets)) planned, \(statusText). Recommended \(Int(row.band.lowerBound.rounded())) to \(Int(row.band.upperBound.rounded()))."
    }

    private func stepsColor(_ status: StepHealthStatus) -> Color {
        switch status {
        case .low: return .orange
        case .building: return .blue
        case .onTrack: return .green
        }
    }
}
