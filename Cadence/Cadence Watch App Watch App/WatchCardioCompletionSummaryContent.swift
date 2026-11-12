import SwiftUI
import CadenceCore
import CadenceFeatures

/// Shared completion content for every Watch cardio workout (steady, HIIT, boxing): duration plus
/// the heart-rate chart and intensity minute rows built from the finalized `SavedWorkoutSummary`
/// samples. Callers add distance/lap rows and their own actions.
struct WatchCardioCompletionSummaryContent<Extra: View>: View {
    let summary: WatchWorkoutManager.SavedWorkoutSummary
    let profile: CardioIntensityProfile
    let durationLabel: String
    @ViewBuilder let extraRows: () -> Extra

    var body: some View {
        let presentation = WatchCardioCompletionSummaryPresenter.present(
            samples: summary.hrSamples, duration: summary.duration,
            averageBPM: summary.avgHR, maximumBPM: summary.maxHR, profile: profile)
        VStack(spacing: 8) {
            row(durationLabel, Self.formatTime(summary.duration))
            if presentation.showsHeartRateChart {
                WatchHeartRateSection(
                    hrSamples: presentation.hrSamples,
                    intensityProfile: profile,
                    sessionDuration: summary.duration)
                    .padding(.horizontal, 20)
            }
            extraRows()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(.caption, design: .monospaced).bold())
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
    }

    private static func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
