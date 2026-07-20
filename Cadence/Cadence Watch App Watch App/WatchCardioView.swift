import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchCardioView: View {
    let metrics: CardioMetricsModel
    let kind: WorkoutConfigurationSpec.CardioKind

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatElapsed())
                    .font(.system(size: 34, weight: .heavy, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 2)

                if kind != .swim {
                    metricRow("Distance", metrics.formatDistance())
                }

                paceOrSpeedRow

                if kind == .swim {
                    metricRow("Lengths", "\(metrics.lapCount + metrics.manualLapCount)")
                    metricRow("Distance", metrics.formatDistance())
                }

                if kind == .rowing {
                    metricRow("Split", metrics.formatSplit())
                }

                if kind != .swim {
                    metricRow("Heart rate", hrText)
                }

                metricRow("Lap", "\(metrics.lapCount + metrics.manualLapCount)")

                if metrics.isAutoPaused {
                    Text("Auto-paused")
                        .font(.headline).foregroundStyle(.yellow).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(.yellow.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
        .background(zoneBackgroundColor)
    }

    @ViewBuilder
    private var paceOrSpeedRow: some View {
        switch kind {
        case .run, .walk:
            metricRow("Pace", metrics.formatPace())
        case .cycle:
            metricRow("Speed", metrics.formatSpeed())
        default:
            EmptyView()
        }
    }

    private func formatElapsed() -> String {
        let total = max(0, Int(metrics.elapsed))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.bold()).monospacedDigit()
        }
    }

    private var hrText: String {
        guard let bpm = metrics.hrBPM else { return "--" }
        return "\(Int(bpm)) · Z\(metrics.hrZone)"
    }

    private var zoneBackgroundColor: Color {
        switch metrics.hrZone {
        case 1: return Color.cyan.opacity(0.15)
        case 2: return Color.green.opacity(0.15)
        case 3: return Color.yellow.opacity(0.15)
        case 4: return Color.orange.opacity(0.15)
        case 5: return Color.red.opacity(0.15)
        default: return Color.clear
        }
    }
}
