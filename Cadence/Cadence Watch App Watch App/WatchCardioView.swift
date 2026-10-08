import SwiftUI
import CadenceCore
import CadenceFeatures

/// Watch redesign §5 I2 — steady cardio: a big-number stack (distance and pace when there is GPS,
/// otherwise time), heart rate with its zone and the elapsed time, and the plan's target
/// underneath. Always On keeps the numbers and drops the tint.
struct WatchCardioView: View {
    let metrics: CardioMetricsModel
    let kind: WorkoutConfigurationSpec.CardioKind
    let spec: WorkoutConfigurationSpec

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(AppSettings.self) private var watchSettings

    var body: some View {
        let presentation = WatchCardioLivePresenter.present(
            elapsed: metrics.elapsed, bpm: metrics.hrBPM, distanceMeters: metrics.distanceMeters,
            heartRateEnabled: metrics.heartRateEnabled, gpsEnabled: metrics.gpsEnabled,
            distanceUnit: metrics.distanceUnit,
            intensityProfile: CardioIntensityProfile.resolved(
                userEnteredMaximumHR: watchSettings.cardioMaximumHROverride,
                age: watchSettings.userAge)
        )
        VStack(alignment: .leading, spacing: 4) {
            if kind == .swim {
                if let poolLength = spec.poolLengthMeters {
                    Text("Laps").font(.caption)
                    bigNumber("\(metrics.lapCount)", size: 42)
                        .accessibilityLabel(Text("\(metrics.lapCount) laps"))
                        .accessibilityIdentifier("watch.swim.laps")
                    Text("\(Int(poolLength)) m per lap").font(.caption2).foregroundStyle(.secondary)
                }
                bigNumber(String(format: "%.0f m", metrics.distanceMeters), size: 30)
                    .accessibilityLabel(Text("Distance \(Int(metrics.distanceMeters)) meters"))
                    .accessibilityIdentifier("watch.cardio.distance")
                Text(presentation.elapsedText).monospacedDigit().font(.footnote)
                Text("Hold Digital Crown to unlock").font(.caption2).foregroundStyle(.secondary)
            } else if let distance = presentation.distanceText {
                bigNumber(distance, size: 30)
                    .accessibilityLabel(Text("Distance \(distance)"))
                    .accessibilityIdentifier("watch.cardio.distance")
                bigNumber(metrics.formatPace(), size: 24)
                    .accessibilityLabel(Text("Pace \(metrics.formatPace())"))
            } else {
                bigNumber(presentation.elapsedText, size: 32)
                    .accessibilityLabel(Text("Elapsed time \(presentation.elapsedText)"))
            }
            HStack {
                if let bpm = presentation.bpmText {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                        Text(bpm).monospacedDigit()
                        if let zone = presentation.hrZone { Text(verbatim: "Z\(zone)") }
                    }
                    .foregroundStyle(zoneColor(presentation.hrTint))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("\(bpm) beats per minute"))
                    .accessibilityIdentifier("watch.cardio.bpm")
                }
                Spacer(minLength: 4)
                if kind != .swim && presentation.distanceText != nil {
                    Text(presentation.elapsedText).monospacedDigit()
                        .accessibilityLabel(Text("Elapsed time \(presentation.elapsedText)"))
                }
            }
            .font(.footnote.weight(.semibold))
            if let intensity = presentation.relativeIntensity, intensity != .unknown {
                Text(intensity.displayName)
                    .font(.caption2.bold())
                    .foregroundStyle(zoneColor(presentation.hrTint))
                    .accessibilityIdentifier("watch.cardio.intensity")
            }
            if let target = WatchCardioPlanTarget.text(durationSeconds: spec.plannedDurationSeconds, zone: spec.targetZone) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target).font(.caption2).foregroundStyle(WatchTone.accent)
                    if let progress = WatchCardioPlanTarget.progress(elapsed: metrics.elapsed,
                                                                     durationSeconds: spec.plannedDurationSeconds) {
                        ProgressView(value: progress).tint(WatchTone.accent)
                            .accessibilityLabel(Text("Planned time"))
                    }
                }
                .padding(.top, 2)
                .accessibilityIdentifier("watch.cardio.planTarget")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 6)
        .background(isLuminanceReduced || !presentation.showsHeartRate
                    ? Color.clear : zoneColor(presentation.hrTint).opacity(0.12))
    }

    private func bigNumber(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
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
