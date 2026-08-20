import SwiftUI
import CadenceCore
import CadenceFeatures

struct HomeWeeklyVolumeSection: View {
    let rows: [HomeDashboardState.VolumeRow]
    let totalVolumeKg: Double
    let unit: MeasurementUnitPreference

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly Volume").font(.headline)
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Text(row.displayName).frame(width: 116, alignment: .leading)
                    ProgressView(value: row.normalized).tint(tint(for: row))
                    VStack(alignment: .trailing) {
                        Text("\(formattedSets(row.sets)) sets")
                            .font(.caption.weight(.semibold))
                        if row.status == .aboveRecoveryRange {
                            Label("Above recovery range", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(width: 88, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(row.displayName)
                .accessibilityValue("\(formattedSets(row.sets)) sets, \(row.rangeStatus)")
                .accessibilityIdentifier("home.volume.\(row.part.rawValue)")
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
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .orange)
        .accessibilityIdentifier("home.volume")
    }

    private func formattedSets(_ sets: Double) -> String {
        sets.formatted(.number.precision(.fractionLength(sets.rounded() == sets ? 0 : 1)))
    }

    private func tint(for row: HomeDashboardState.VolumeRow) -> Color {
        switch row.status {
        case .belowStartingRange: return .yellow
        case .productive: return .green
        case .aboveRecoveryRange: return .red
        }
    }
}
