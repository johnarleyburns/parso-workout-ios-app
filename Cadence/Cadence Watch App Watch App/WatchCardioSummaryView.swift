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

            summaryRow("Duration", formatTime(summary.duration))
            if let avg = summary.avgHR {
                summaryRow("Avg / Max HR", "\(Int(avg)) / \(Int(summary.maxHR ?? avg))")
            }
            if summary.distanceMeters > 0 {
                summaryRow("Distance", metrics.formatDistance())
            }
            if let laps = lapText {
                summaryRow("Laps", laps)
            }
            summaryRow("Active kcal", "\(Int(summary.activeKcal))")

            Button("Save") { onSave() }
                .buttonStyle(.borderedProminent).tint(.green)
            Button("Discard") { onDiscard() }
                .buttonStyle(.plain).foregroundStyle(.secondary)

            Text("Synced to iPhone via Health")
                .font(.caption2).foregroundStyle(.tertiary).padding(.top, 4)
            Spacer()
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.bold()).monospacedDigit()
        }
        .padding(.horizontal, 20)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
