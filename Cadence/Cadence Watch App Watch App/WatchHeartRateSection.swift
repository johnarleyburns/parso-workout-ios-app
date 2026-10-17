import SwiftUI
import Charts
import CadenceCore
import CadenceFeatures

/// Heart-rate heading, zone-banded graph, and Avg/Max rows shared by the cardio and strength
/// watch summaries. Renders nothing when the workout recorded no heart-rate samples.
struct WatchHeartRateSection: View {
    let hrSamples: [HRSamplePoint]
    @Environment(AppSettings.self) private var watchSettings

    private var zoneMaxHR: Double {
        CardioIntensityProfile.resolved(userEnteredMaximumHR: watchSettings.cardioMaximumHROverride,
                                        age: watchSettings.userAge).maximumHR
            ?? CardioMath.defaultMaxHR(age: watchSettings.userAge)
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
        let presentation = WatchCardioSummaryPresenter.present(hrSamples: hrSamples)
        if presentation.showsHeartRate {
            let domain = HRZoneBands.domain(bpms: hrSamples.map(\.bpm), maxHR: zoneMaxHR)
            VStack(spacing: 8) {
                Text("Heart Rate")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("watchSummary.hrHeading")
                Chart {
                    ForEach(HRZoneBands.bands(maxHR: zoneMaxHR, domain: domain), id: \.zone) { band in
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
                .chartYScale(domain: domain)
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) }
                .frame(height: 82)
                .accessibilityLabel("Heart rate graph")
                if let avg = presentation.averageBPM {
                    row(String(localized: "Avg HR"), "\(Int(avg.rounded()))")
                }
                if let max = presentation.maximumBPM {
                    row(String(localized: "Max HR"), "\(Int(max.rounded()))")
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(.caption, design: .monospaced).bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
