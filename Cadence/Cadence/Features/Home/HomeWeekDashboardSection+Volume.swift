import SwiftUI
import CadenceCore
import CadenceFeatures

extension HomeWeekDashboardSection {
    /// One muscle group's weekly sets. This is the resolution that answers
    /// "did I actually train my adductors this week?".
    func volumeRow(_ row: HomeDashboardState.VolumeRow) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text(row.displayName)
                    .font(.caption)
                    .foregroundStyle(row.isTracked ? tint(for: row.zone) : .secondary)
            }
            .frame(width: 116, alignment: .leading)
            ProgressView(value: row.normalized).tint(tint(for: row.zone))
            HStack(spacing: 4) {
                Text("\(formattedSets(row.sets)) sets")
                    .font(.caption.weight(.semibold).monospacedDigit())
                if let warning = volumeWarning(for: row) {
                    Button { volumeWarningMessage = warning } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Volume warning for \(row.displayName)")
                }
            }
            .frame(width: 88, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.displayName)
        .accessibilityValue("\(formattedSets(row.sets)) sets")
        .accessibilityHint(row.isTracked ? "" : "Not a tracked muscle group")
        .accessibilityIdentifier("home.volume.\(row.group.rawValue)")
    }

    func formattedSets(_ sets: Double) -> String {
        sets.formatted(.number.precision(.fractionLength(sets.rounded() == sets ? 0 : 1)))
    }

    func volumeWarning(for row: HomeDashboardState.VolumeRow) -> String? {
        switch row.zone {
        case .belowMinimum:
            let remaining = max(0, WeeklySetProgress.minimum - row.sets)
            return "\(row.displayName) is \(formattedSets(remaining)) sets below the current minimum. You can add work if that fits your recovery and plan."
        case .aboveMaximum:
            return "\(row.displayName) is above the 12-set maximum for this week. Consider reducing volume or allowing more recovery before adding more work."
        case .building, .productive:
            return nil
        }
    }

    func tint(for zone: WeeklySetZone) -> Color {
        switch zone.tintRole {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return .green
        }
    }
}
