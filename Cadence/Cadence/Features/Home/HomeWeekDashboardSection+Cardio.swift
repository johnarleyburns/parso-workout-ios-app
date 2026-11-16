import SwiftUI
import Charts
import CadenceCore
import CadenceFeatures

extension HomeWeekDashboardSection {
    var cardioOverview: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(CardioMinutesDisplay.moderateEquivalent(
                    dashboard.cardioDetail.moderateEquivalentMinutes,
                    target: dashboard.cardioDetail.targetMinutes))
                    .font(.title2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(cardioTint)
                    .accessibilityIdentifier("home.week.cardio.progressTotal")
                Text("Moderate-equivalent minutes")
                    .font(.subheadline).foregroundStyle(.secondary)
                weeklyCardioProgress
            }
            if dashboard.cardioDetail.zoneMinutes.values.contains(where: { $0 > 0 }) {
                trainingZoneSummary
            }
            DisclosureGroup(isExpanded: $showsCardioDetails) {
                VStack(alignment: .leading, spacing: 20) {
                    cardioMinutes
                    if let dose = dashboard.activityDose { activityDose(dose) }
                }
                .padding(.top, 12)
            } label: {
                Text("Details").font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("home.week.cardio.details")
        }
    }

    private var weeklyCardioProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: dashboard.cardio.normalized)
                .tint(cardioTint)
                .overlay {
                    GeometryReader { geometry in
                        Rectangle().fill(.primary)
                            .frame(width: 2, height: 10)
                            .position(x: geometry.size.width * minimumProgress,
                                      y: geometry.size.height / 2)
                    }
                    .accessibilityHidden(true)
                }
                .accessibilityLabel("Weekly cardio progress")
                .accessibilityValue(CardioMinutesDisplay.moderateEquivalent(
                    dashboard.cardioDetail.moderateEquivalentMinutes,
                    target: dashboard.cardioDetail.targetMinutes))
            Text("Minimum \(Int(WeeklyCardioProgress.minimum)) · Goal \(Int(dashboard.cardioDetail.targetMinutes)) min")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var minimumProgress: Double {
        min(1, max(0, WeeklyCardioProgress.minimum / max(1, dashboard.cardioDetail.targetMinutes)))
    }

    private var trainingZoneSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training zones").font(.subheadline.weight(.semibold))
            Chart {
                ForEach(TrainingZone.allCases, id: \.self) { zone in
                    let minutes = dashboard.cardioDetail.zoneMinutes[zone] ?? 0
                    if minutes > 0 {
                        SectorMark(angle: .value("Minutes", minutes),
                                   innerRadius: .ratio(0.68), angularInset: 2)
                            .foregroundStyle(zoneColor(zone))
                            .accessibilityLabel(zone.displayName)
                            .accessibilityValue(CardioMinutesDisplay.zone(minutes))
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 150)
            .accessibilityIdentifier("cardio.trainingZones.chart")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)],
                      alignment: .leading, spacing: 8) {
                ForEach(TrainingZone.allCases, id: \.self) { zone in
                    let minutes = dashboard.cardioDetail.zoneMinutes[zone] ?? 0
                    if minutes > 0 {
                        HStack(spacing: 6) {
                            Circle().fill(zoneColor(zone)).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text("\(zone.displayName) · \(CardioMinutesDisplay.zone(minutes))")
                                .font(.subheadline).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    /// Keep the weekly activity color consistent with the other dashboard surfaces.
    var cardioTint: Color {
        CadenceTheme.weeklyTint(WeeklyCardioProgress.tintRole(for: dashboard.cardioDetail.moderateEquivalentMinutes))
    }

    private var cardioMinutes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cardio Minutes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(cardioTint)
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
                    .foregroundStyle(cardioTint)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.week.cardio.total")
            Text("Goal \(Int(WeeklyCardioProgress.target)) min moderate-equivalent; \(Int(WeeklyCardioProgress.minimum)) min is the guideline minimum.")
                .font(.caption2).foregroundStyle(.secondary)
            if dashboard.cardioDetail.unclassifiedMinutes > 0 {
                Text(CardioMinutesDisplay.unclassified(dashboard.cardioDetail.unclassifiedMinutes))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            CoachSourcesLink(
                citationIds: dashboard.cardioDetail.citationIDs,
                contexts: Dictionary(uniqueKeysWithValues: dashboard.cardioDetail.citationIDs.map {
                    ($0, dashboard.cardioDetail.explanation)
                }),
                identifier: "home.week.cardio.science")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.week.cardioMinutes")
    }

    private func zoneColor(_ zone: TrainingZone) -> Color {
        switch zone {
        case .z1: return .blue
        case .z2: return .green
        case .z3: return .yellow
        case .z4: return .orange
        case .z5: return .red
        }
    }
}
