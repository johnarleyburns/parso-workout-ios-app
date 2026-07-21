import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchCardioSummaryView: View {
    let summary: WatchWorkoutManager.SavedWorkoutSummary
    let metrics: CardioMetricsModel
    let lapText: String?
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28)).foregroundStyle(.green)

            summaryRow("Total", formatTime(summary.duration))
            if let avg = summary.avgHR {
                summaryRow("Avg HR", "\(Int(avg))")
            }
            if summary.distanceMeters > 0 {
                summaryRow("Distance", metrics.formatDistance())
            }
            if let laps = lapText {
                summaryRow("Laps", laps)
            }

            Button("Save") { onSave() }
                .buttonStyle(.borderedProminent).tint(.green)
            Button("Discard") { onDiscard() }
                .buttonStyle(.plain).foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(.caption, design: .monospaced).bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 20)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
