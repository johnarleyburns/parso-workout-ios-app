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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week").font(.headline)
            progressRow(id: "home.week.strength", title: "Strength", value: dashboard.strength.displayText,
                        progress: dashboard.strength.normalized,
                        tint: dashboard.strength.isAtOrAboveTarget ? .green : .yellow)
            progressRow(id: "home.week.cardio", title: "Cardio", value: dashboard.cardio.displayText,
                        progress: dashboard.cardio.normalized,
                        tint: dashboard.cardio.isAtOrAboveTarget ? .green : .yellow)
            progressRow(id: "home.week.volume", title: "Volume", value: dashboard.volumeCoverage.displayText,
                        progress: dashboard.volumeCoverage.normalized,
                        tint: dashboard.volumeCoverage.isAtOrAboveTarget ? .green : .yellow)

            if volumeExpanded {
                expandedWeek
            }

            Button(volumeExpanded ? "Show less" : "Show more…") {
                withAnimation { volumeExpanded.toggle() }
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier(volumeExpanded ? "home.week.showLess" : "home.week.showMore")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: .green)
    }

    private var expandedWeek: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            workoutGroup(title: "Strength", entries: strengthEntries)
            workoutGroup(title: "Cardio", entries: cardioEntries)

            Divider().padding(.top, 2)
            Text("Volume")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityIdentifier("home.week.volumeHeading")
            ForEach(dashboard.volume) { row in
                volumeRow(row)
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
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.thisWeek.expanded")
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
                .foregroundStyle(tint(for: row))
            ProgressView(value: row.normalized).tint(tint(for: row))
            VStack(alignment: .trailing) {
                Text("\(formattedSets(row.sets)) sets")
                    .font(.caption.weight(.semibold))
                if row.status == .aboveRecoveryRange {
                    Label("Above recovery range", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }
            .frame(width: 88, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.displayName)
        .accessibilityValue("\(formattedSets(row.sets)) sets, \(row.rangeStatus)")
        .accessibilityIdentifier("home.volume.\(row.part.rawValue)")
    }

    private func progressRow(id: String, title: String, value: String,
                             progress: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline).foregroundStyle(tint)
                Spacer()
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            ProgressView(value: progress).tint(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private func formattedSets(_ sets: Double) -> String {
        sets.formatted(.number.precision(.fractionLength(sets.rounded() == sets ? 0 : 1)))
    }

    private func tint(for row: HomeDashboardState.VolumeRow) -> Color {
        switch row.status {
        case .belowStartingRange, .aboveRecoveryRange: return .yellow
        case .productive: return .green
        }
    }
}
