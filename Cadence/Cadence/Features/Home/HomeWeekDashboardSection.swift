import SwiftUI
import CadenceCore
import CadenceFeatures

struct HomeWeekDashboardSection: View {
    let dashboard: HomeDashboardState
    @Binding var volumeExpanded: Bool
    let strengthEntries: [TodayActivityPresenter.Entry]
    let cardioEntries: [TodayActivityPresenter.Entry]
    let totalVolumeKg: Double
    let unit: MeasurementUnitPreference
    let onOpenWorkout: (TodayActivityPresenter.Entry) -> Void
    let onOpenCoachSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
            header
            progressRow(id: "home.week.strength", title: "Strength", value: dashboard.strength.displayText,
                        progress: dashboard.strength.normalized,
                        tint: dashboard.strength.isAtOrAboveTarget ? .green : .yellow)
            progressRow(id: "home.week.cardio", title: "Cardio", value: dashboard.cardio.displayText,
                        progress: dashboard.cardio.normalized,
                        tint: dashboard.cardio.isAtOrAboveTarget ? .green : .yellow,
                        caption: dashboard.cardioDetail.summary)
            progressRow(id: "home.week.volume", title: "Volume",
                        value: dashboard.volumeCoverage.displayText,
                        progress: dashboard.volumeCoverage.normalized,
                        tint: tint(for: WeeklySetProgress.zone(for: dashboard.volumeCoverage.completed)),
                        caption: weeklySetCaption)
            progressRow(id: "home.week.muscles", title: "Muscles",
                        value: dashboard.muscleCoverage.displayText,
                        progress: dashboard.muscleCoverage.normalized,
                        tint: tint(for: WeeklySetProgress.zone(for: dashboard.muscleCoverage.completed)),
                        caption: weeklySetCaption)

            if volumeExpanded {
                expandedWeek
            }

            Button(volumeExpanded ? "Show less" : "Show more…") {
                withAnimation { volumeExpanded.toggle() }
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier(volumeExpanded ? "home.week.showLess" : "home.week.showMore")
        }
        .padding(CGFloat(LayoutMetrics.cardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .green)
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

    private var expandedWeek: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            workoutGroup(title: "Strength", entries: strengthEntries)
            workoutGroup(title: "Cardio", entries: cardioEntries)

            Divider().padding(.top, 2)
            cardioMinutes

            Divider().padding(.top, 2)
            Text("Volume")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityIdentifier("home.week.volumeHeading")
            ForEach(dashboard.volume) { row in
                volumeRow(row)
            }
            if let citation = CitationRegistry.citation(forId: CitationRegistry.iversenTimeEfficient2021.id) {
                CitationLink(citation: citation,
                             context: "Weekly set volume is shown on a shared 4-to-12-set scale for each muscle group.",
                             compact: true)
            }
            Divider()
            HStack {
                Text("Total Volume").font(.subheadline.weight(.semibold))
                Spacer()
                Text(WorkoutMath.tonnageLabel(volumeKg: totalVolumeKg, unit: unit))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.volume.total")

            Divider().padding(.top, 2)
            muscles
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.thisWeek.expanded")
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
                Text("\(Int(dashboard.cardioDetail.moderateEquivalentMinutes.rounded())) of \(Int(dashboard.cardioDetail.targetMinutes)) min")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.week.cardio.total")
            Text(dashboard.cardioDetail.explanation)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let citation = CitationRegistry.citation(forId: dashboard.cardioDetail.citationID) {
                CitationLink(citation: citation, context: dashboard.cardioDetail.explanation, compact: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.week.cardioMinutes")
    }

    /// Field test 2026-08-19 #8: muscle groups are too coarse to answer "have I
    /// trained my adductors this week?". Every catalog muscle gets a line.
    private var muscles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Muscles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
                .accessibilityIdentifier("home.week.musclesHeading")
            Text(weeklySetCaption)
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(dashboard.muscles) { row in
                muscleRow(row)
            }
            if let citation = CitationRegistry.citation(forId: CitationRegistry.iversenTimeEfficient2021.id) {
                CitationLink(citation: citation,
                             context: "Weekly set volume is shown on a shared 4-to-12-set scale for each tracked muscle.",
                             compact: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.week.muscles")
    }

    private func muscleRow(_ row: HomeDashboardState.MuscleRow) -> some View {
        HStack(spacing: 10) {
            Text(row.displayName)
                .font(.caption)
                .frame(width: 116, alignment: .leading)
                .foregroundStyle(tint(for: row.zone))
            ProgressView(value: row.normalized)
                .tint(tint(for: row.zone))
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(formattedSets(row.sets)) sets")
                    .font(.caption.weight(.semibold).monospacedDigit())
                Text(row.rangeText)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 88, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.displayName)
        .accessibilityValue("\(formattedSets(row.sets)) sets, \(row.rangeText)")
        .accessibilityIdentifier("home.muscle.\(row.muscleID)")
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

    private func volumeRow(_ row: HomeDashboardState.VolumeRow) -> some View {
        HStack(spacing: 10) {
            Text(row.displayName)
                .frame(width: 116, alignment: .leading)
                .foregroundStyle(tint(for: row.zone))
            ProgressView(value: row.normalized).tint(tint(for: row.zone))
            VStack(alignment: .trailing) {
                Text("\(formattedSets(row.sets)) sets")
                    .font(.caption.weight(.semibold))
                if row.zone == .aboveMaximum {
                    Label("Above 12-set maximum", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 88, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.displayName)
        .accessibilityValue("\(formattedSets(row.sets)) sets, \(row.rangeText)")
        .accessibilityIdentifier("home.volume.\(row.part.rawValue)")
    }

    private func progressRow(id: String, title: String, value: String,
                             progress: Double, tint: Color,
                             caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline).foregroundStyle(tint)
                Spacer()
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            ProgressView(value: progress).tint(tint)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private func formattedSets(_ sets: Double) -> String {
        sets.formatted(.number.precision(.fractionLength(sets.rounded() == sets ? 0 : 1)))
    }

    private var weeklySetCaption: String {
        "4 minimum · 8+ productive · 12 maximum"
    }

    private func tint(for zone: WeeklySetZone) -> Color {
        switch zone.tintRole {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return .green
        }
    }
}
