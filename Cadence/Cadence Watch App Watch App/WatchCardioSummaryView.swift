import SwiftUI
import Charts
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
    @Environment(AppSettings.self) private var watchSettings

    private var zoneMaxHR: Double {
        CardioIntensityProfile.resolved(userEnteredMaximumHR: watchSettings.cardioMaximumHROverride,
                                        age: watchSettings.userAge).maximumHR
            ?? CardioMath.defaultMaxHR(age: watchSettings.userAge)
    }

    private var zoneDomain: ClosedRange<Double> {
        HRZoneBands.domain(bpms: summary.hrSamples.map(\.bpm), maxHR: zoneMaxHR)
    }

    private func zoneColor(_ tint: HRZoneTint) -> Color {
        switch tint {
        case .zone1: .cyan
        case .zone2: .green
        case .zone3: .yellow
        case .zone4: .orange
        case .zone5: .red
        case .neutral: .secondary
        }
    }

    var body: some View {
        let presentation = WatchCardioSummaryPresenter.present(hrSamples: summary.hrSamples)
        ScrollView {
          VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28)).foregroundStyle(.green)

            summaryRow(String(localized: "Total"), formatTime(summary.duration))
            if presentation.showsHeartRate {
                Text("Heart Rate")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("watchSummary.hrHeading")
                Chart {
                    ForEach(HRZoneBands.bands(maxHR: zoneMaxHR, domain: zoneDomain), id: \.zone) { band in
                        RectangleMark(yStart: .value("Zone start", band.lower),
                                      yEnd: .value("Zone end", band.upper))
                            .foregroundStyle(zoneColor(band.tint).opacity(0.3))
                    }
                    ForEach(Array(presentation.hrSamples.enumerated()), id: \.offset) { _, sample in
                        LineMark(x: .value("Elapsed", sample.t), y: .value("BPM", sample.bpm))
                            .foregroundStyle(.white)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)
                        if presentation.hrSamples.count == 1 {
                            PointMark(x: .value("Elapsed", sample.t), y: .value("BPM", sample.bpm))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .chartYScale(domain: zoneDomain)
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) }
                .frame(height: 82)
                .padding(.horizontal, 12)
                .accessibilityLabel("Heart rate graph")
                if let avg = presentation.averageBPM {
                    summaryRow(String(localized: "Avg HR"), "\(Int(avg.rounded()))")
                }
                if let max = presentation.maximumBPM {
                    summaryRow(String(localized: "Max HR"), "\(Int(max.rounded()))")
                }
            }
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
