import SwiftUI
import Charts
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

extension HomeWeekDashboardSection {
    var cardioOverview: some View {
        VStack(alignment: .leading, spacing: 20) {
            guidelineCreditRow
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
                Text("Details").font(.subheadline)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("home.week.cardio.details")
        }
        .font(.subheadline)
    }

    /// Replaces the old big number + progress bar + "Minimum/Goal" caption
    /// with one plain two-sided row, matching Muscle coverage's single-size
    /// text pattern instead of standing out as an oversized stat.
    private var guidelineCreditRow: some View {
        HStack {
            Text("Guideline credit")
                .font(.headline)
            Spacer()
            Text(CardioMinutesDisplay.guidelineCreditFraction(
                dashboard.cardioDetail.moderateEquivalentMinutes,
                target: dashboard.cardioDetail.targetMinutes))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(cardioTint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.week.cardio.progressTotal")
    }

    private var trainingZoneSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training zones")
            Chart {
                ForEach(TrainingZone.allCases, id: \.self) { zone in
                    let minutes = dashboard.cardioDetail.zoneMinutes[zone] ?? 0
                    if minutes > 0 {
                        BarMark(x: .value("Zone", zone.displayName), y: .value("Minutes", minutes))
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
                                .monospacedDigit()
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
                .font(.headline)
                .foregroundStyle(cardioTint)
                .accessibilityIdentifier("home.week.cardioHeading")
            HStack {
                Text("Actual exercise")
                Spacer()
                Text(CardioMinutesDisplay.logged(dashboard.cardioDetail.loggedMinutes))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ForEach(dashboard.cardioDetail.lines, id: \.label) { line in
                HStack {
                    Text(line.label)
                    Spacer()
                    Text(line.minutes).monospacedDigit().foregroundStyle(.secondary)
                    Text("→").foregroundStyle(.tertiary)
                    Text(line.credit).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("home.week.cardio.\(line.label.lowercased())")
            }
            HStack {
                Text("Moderate-equivalent")
                Spacer()
                Text(CardioMinutesDisplay.moderateEquivalent(
                    dashboard.cardioDetail.moderateEquivalentMinutes,
                    target: dashboard.cardioDetail.targetMinutes))
                    .monospacedDigit()
                    .foregroundStyle(cardioTint)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.week.cardio.total")
            Text("Goal \(Int(WeeklyCardioProgress.target)) min moderate-equivalent; \(Int(WeeklyCardioProgress.minimum)) min is the guideline minimum.")
                .foregroundStyle(.secondary)
            if dashboard.cardioDetail.unclassifiedMinutes > 0 {
                Text(CardioMinutesDisplay.unclassified(dashboard.cardioDetail.unclassifiedMinutes))
                    .foregroundStyle(.secondary)
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
