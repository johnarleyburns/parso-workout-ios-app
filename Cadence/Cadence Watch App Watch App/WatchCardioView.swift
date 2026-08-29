import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchCardioView: View {
    let metrics: CardioMetricsModel
    let kind: WorkoutConfigurationSpec.CardioKind

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let presentation = WatchCardioLivePresenter.present(
            elapsed: metrics.elapsed, bpm: metrics.hrBPM, distanceMeters: metrics.distanceMeters,
            heartRateEnabled: metrics.heartRateEnabled, gpsEnabled: metrics.gpsEnabled,
            distanceUnit: metrics.distanceUnit
        )
        VStack(spacing: 4) {
            Text(presentation.elapsedText)
                .font(.system(size: 34, weight: .heavy, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Elapsed time \(presentation.elapsedText)")

            if let bpm = presentation.bpmText {
                Text(bpm)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(zoneColor(presentation.hrTint))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("\(bpm) beats per minute")
                    .accessibilityIdentifier("watch.cardio.bpm")
            }

            if let distance = presentation.distanceText {
                HStack {
                    Text(distance)
                        .font(.caption.bold())
                        .monospacedDigit()
                        .accessibilityLabel("Distance \(distance)")
                        .accessibilityIdentifier("watch.cardio.distance")
                    Spacer()
                }
            }
        }
        .padding()
        .background(zoneColor(presentation.hrTint).opacity(presentation.showsHeartRate ? 0.15 : 0))
    }

    private func zoneColor(_ tint: HRZoneTint) -> Color {
        switch tint {
        case .zone1: return .cyan
        case .zone2: return .green
        case .zone3: return .yellow
        case .zone4: return .orange
        case .zone5: return .red
        case .neutral: return .secondary
        }
    }
}
