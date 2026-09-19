import SwiftUI
import CadenceCore
import CadenceFeatures

struct HomeWeekDashboardSection: View {
    let dashboard: HomeDashboardState
    @Binding var strengthExpanded: Bool
    @Binding var cardioExpanded: Bool
    @Binding var volumeExpanded: Bool
    @Binding var muscleMapPanel: MuscleMapPanel
    let strengthEntries: [TodayActivityPresenter.Entry]
    let cardioEntries: [TodayActivityPresenter.Entry]
    let muscleHistory: [HomeMuscleHistory]
    let muscleHistoryByPerformer: [String: [HomeMuscleHistory]]
    let weeklyVolumeByPerformer: [String: [MuscleGroup: Double]]
    let weeklyVolumeKgByPerformer: [String: Double]
    let weeklyVolumePerformers: [VolumeSummaryPerformer]
    let totalVolumeKg: Double
    let unit: MeasurementUnitPreference
    let onOpenWorkout: (TodayActivityPresenter.Entry) -> Void
    let onOpenCoachSettings: () -> Void
    @State fileprivate var volumeWarningMessage: String?
    /// Keep selection as a small value instead of copying the full weekly history
    /// graph into SwiftUI state. The old `HomeMuscleHistory?` selection made every
    /// tap compare all exercise/set rows before the sheet could present.
    @State private var selectedMuscleGroup: MuscleGroup?
    @State private var selectedVolumePerformerKey: String?

    private var selectedVolume: [MuscleGroup: Double] {
        guard let selectedVolumePerformerKey,
              let value = weeklyVolumeByPerformer[selectedVolumePerformerKey] else {
            return Dictionary(uniqueKeysWithValues: dashboard.volume.map { ($0.group, $0.sets) })
        }
        return value
    }

    private var displayedVolumeRows: [HomeDashboardState.VolumeRow] {
        guard !weeklyVolumeByPerformer.isEmpty else { return dashboard.volume }
        let tracked = Set(dashboard.volume.filter(\.isTracked).map(\.group))
        return HomeDashboardPresenter.volumeRows(setsByGroup: selectedVolume,
                                                 tracked: tracked)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
            header
            muscleMapSummary
            disclosureRow(title: "Strength", value: dashboard.strength.displayText,
                          progress: dashboard.strength.normalized,
                          tint: dashboard.strength.isAtOrAboveTarget ? .green : .yellow,
                          expanded: $strengthExpanded, identifier: "home.week.strength") {
                workoutGroup(title: "Strength", entries: strengthEntries)
            }
            disclosureRow(title: "Cardio", value: dashboard.cardio.displayText,
                          progress: dashboard.cardio.normalized,
                          tint: dashboard.cardio.isAtOrAboveTarget ? .green : .yellow,
                          expanded: $cardioExpanded, identifier: "home.week.cardio") {
                VStack(alignment: .leading, spacing: 10) {
                    workoutGroup(title: "Cardio", entries: cardioEntries)
                    cardioMinutes
                    if let dose = dashboard.activityDose { activityDose(dose) }
                }
            }
            disclosureRow(title: "Volume", value: dashboard.volumeCoverage.displayText,
                          progress: dashboard.volumeCoverage.normalized,
                          tint: tint(for: WeeklySetProgress.zone(for: dashboard.volumeCoverage.completed)),
                          expanded: $volumeExpanded, identifier: "home.week.volume") {
                volumeDetail
            }
        }
        .padding(CGFloat(LayoutMetrics.cardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .green)
        .alert("Volume warning", isPresented: Binding(
            get: { volumeWarningMessage != nil },
            set: { if !$0 { volumeWarningMessage = nil } })) {
                Button("OK", role: .cancel) { volumeWarningMessage = nil }
            } message: {
                Text(volumeWarningMessage ?? "")
            }
        .onAppear {
            if selectedVolumePerformerKey == nil {
                selectedVolumePerformerKey = weeklyVolumePerformers.first?.id
            }
        }
        .onChange(of: weeklyVolumePerformers) { _, next in
            if let selectedVolumePerformerKey,
               next.contains(where: { $0.id == selectedVolumePerformerKey }) { return }
            selectedVolumePerformerKey = next.first?.id
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("This Week").font(.headline)
            Spacer()
            Button {
                Haptics.selection()
                onOpenCoachSettings()
            } label: {
                Image(systemName: "gearshape")
                    .imageScale(.medium)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.trailing, -8)
            .padding(.vertical, -8)
            .accessibilityIdentifier("home.week.coachSettings")
            .accessibilityLabel("Coach and plan settings")
            .accessibilityHint("Opens Coach & Plan preferences")
        }
    }

    private var volumeDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Volume")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityIdentifier("home.week.volumeHeading")
            HStack(spacing: 8) {
                legendItem("Below", color: .blue)
                legendItem("Building", color: .yellow)
                legendItem("Productive", color: .green)
                legendItem("Above", color: .red)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Muscle volume legend: below, building, productive, and above maximum")
            if weeklyVolumePerformers.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(weeklyVolumePerformers) { performer in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedVolumePerformerKey = performer.id
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: selectedVolumePerformerKey == performer.id
                                          ? "largecircle.fill.circle" : "circle")
                                    Text(performer.name)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 36)
                                .background(selectedVolumePerformerKey == performer.id
                                            ? Color.accentColor.opacity(0.14)
                                            : Color.secondary.opacity(0.08),
                                            in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(selectedVolumePerformerKey == performer.id
                                             ? Color.accentColor : .secondary)
                            .accessibilityIdentifier("home.week.volume.performer.\(performer.id)")
                        }
                    }
                }
                .accessibilityIdentifier("home.week.volume.performers")
            }
            ForEach(displayedVolumeRows) { row in
                volumeRow(row)
            }
            CoachSourcesLink(
                citationIds: CitationRegistry.strengthVolumePool.citationIds,
                identifier: "home.week.volume.science")
            HStack {
                Text("Total Volume").font(.subheadline.weight(.semibold))
                Spacer()
                Text(WorkoutMath.tonnageLabel(
                    volumeKg: selectedVolumePerformerKey.flatMap {
                        weeklyVolumeKgByPerformer[$0]
                    } ?? totalVolumeKg,
                    unit: unit))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.volume.total")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.thisWeek.expanded")
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }

    private var muscleMapSummary: some View {
        HomeMuscleMapView(
            dashboard: dashboard,
            volumeRows: displayedVolumeRows,
            selectedPanel: $muscleMapPanel,
            onSelect: { group in
                // Only publish the selected identity. The detail payload is
                // resolved when the sheet is built, keeping the tap path cheap.
                selectedMuscleGroup = group
            },
            onOpenCardio: {
                withAnimation(.easeInOut(duration: 0.18)) { cardioExpanded = true }
            })
        .sheet(item: $selectedMuscleGroup) { group in
            let currentSets = selectedVolume[group] ?? 0
            let selectedHistory = selectedVolumePerformerKey.flatMap {
                muscleHistoryByPerformer[$0]
            } ?? muscleHistory
            let cached = selectedHistory.first(where: { $0.group == group })
            let history = HomeMuscleHistory(
                group: group,
                displayName: cached?.displayName ?? group.displayName,
                creditedSets: currentSets,
                exercises: cached?.exercises ?? [])
            HomeMuscleDetailSheet(history: history, unit: unit)
        }
        .accessibilityIdentifier("home.week.muscleMap")
    }

    private func disclosureRow<Content: View>(title: String, value: String,
                                              progress: Double, tint: Color,
                                              expanded: Binding<Bool>, identifier: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.wrappedValue.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title).font(.headline).foregroundStyle(tint)
                        Spacer()
                        Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ProgressView(value: progress).tint(tint)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(expanded.wrappedValue
                                     ? "\(identifier).showLess"
                                     : "\(identifier).showMore")
            .accessibilityValue(expanded.wrappedValue ? "Expanded" : "Collapsed")
            if expanded.wrappedValue {
                content()
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Field test 2026-08-19 #7: five short but hard sessions read as "158 of 150
    /// min" against 80 minutes on the clock. The weighting is real public-health
    /// arithmetic, so the fix is to show it rather than hide it.
    private var cardioMinutes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cardio Minutes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.teal)
                .accessibilityIdentifier("home.week.cardioHeading")
            HStack {
                Text("Actual exercise").font(.caption)
                Spacer()
                Text(CardioMinutesDisplay.logged(dashboard.cardioDetail.loggedMinutes))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(dashboard.cardioDetail.lines, id: \.label) { line in
                HStack {
                    Text(line.label).font(.caption)
                    Spacer()
                    Text(line.minutes).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text("→").font(.caption2).foregroundStyle(.tertiary)
                    Text(line.credit).font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("home.week.cardio.\(line.label.lowercased())")
            }
            HStack {
                Text("Moderate-equivalent").font(.caption.weight(.semibold))
                Spacer()
                Text(CardioMinutesDisplay.moderateEquivalent(
                    dashboard.cardioDetail.moderateEquivalentMinutes,
                    target: dashboard.cardioDetail.targetMinutes))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.week.cardio.total")
            if dashboard.cardioDetail.unclassifiedMinutes > 0 {
                Text(CardioMinutesDisplay.unclassified(dashboard.cardioDetail.unclassifiedMinutes))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !dashboard.cardioDetail.zoneMinutes.isEmpty {
                Text("Training zones")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 2)
                ForEach(dashboard.cardioDetail.zoneMinutes.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { zone in
                    HStack {
                        Text(zone.displayName).font(.caption)
                        Spacer()
                        Text(CardioMinutesDisplay.zone(dashboard.cardioDetail.zoneMinutes[zone] ?? 0))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            if let citation = CitationRegistry.citation(forId: dashboard.cardioDetail.citationID) {
                CitationLink(citation: citation, context: dashboard.cardioDetail.explanation, compact: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.week.cardioMinutes")
    }

    private func activityDose(_ dose: WeeklyActivitySummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Activity Dose")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
            HStack {
                Text("Actual activity")
                Spacer()
                Text("\(Int(dose.actualActivityMinutes.rounded())) min")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Text("Standard MET-minutes")
                Spacer()
                Text("\(Int(dose.totalStandardMETMinutes.rounded()))")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Text("Strength days")
                Spacer()
                Text("\(dose.strengthDays)").monospacedDigit().foregroundStyle(.secondary)
            }
            if let citation = CitationRegistry.citation(forId: "compendium2024AdultPhysicalActivities") {
                CitationLink(citation: citation,
                             context: "MET-minutes are a separate standardized activity-dose estimate; they are not a replacement for cardio guideline credit.",
                             compact: true)
            }
        }
        .font(.caption)
        .accessibilityIdentifier("home.week.activityDose")
    }

    @ViewBuilder
    private func workoutGroup(title: String, entries: [TodayActivityPresenter.Entry]) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(title == "Strength" ? .green : .teal)
            .accessibilityIdentifier("home.week.group.\(title.lowercased())")

        if entries.isEmpty {
            Text("No \(title.lowercased()) workouts this week.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().padding(.leading, 40) }
                    HomeWeekWorkoutRow(entry: entry) { onOpenWorkout(entry) }
                }
            }
        }
    }

}
