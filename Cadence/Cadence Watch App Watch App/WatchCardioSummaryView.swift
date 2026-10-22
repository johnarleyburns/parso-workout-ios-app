import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchCardioSummaryView: View {
    let summary: WatchWorkoutManager.SavedWorkoutSummary
    let metrics: CardioMetricsModel
    let lapText: String?
    let isSwim: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void
    @Environment(WatchWorkoutManager.self) private var watchManager

    var body: some View {
        ScrollView {
          VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28)).foregroundStyle(.green)

            summaryRow(String(localized: "Total"), formatTime(summary.duration))
            WatchHeartRateSection(hrSamples: summary.hrSamples)
                .padding(.horizontal, 20)
            if summary.distanceMeters > 0 {
                summaryRow(String(localized: "Distance"), isSwim ? String(format: "%.0f m", summary.distanceMeters) : metrics.formatDistance())
            }
            if let laps = lapText {
                summaryRow(String(localized: "Laps"), laps)
            }

            Button("Save") { onSave() }
                .buttonStyle(.borderedProminent).tint(.green)
            if watchManager.phoneSyncState.isInProgress {
                Text("Syncing to iPhone…").font(.caption).foregroundStyle(.secondary)
            } else if !watchManager.pendingCardioCompletions.isEmpty {
                Text("Will sync when iPhone is available").font(.caption).foregroundStyle(.secondary)
            }
            Button("Discard") { onDiscard() }
                .buttonStyle(.plain).foregroundStyle(.secondary)

            Spacer(minLength: 8)
          }
          .padding(.vertical, 8)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(.caption, design: .monospaced).bold())
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
