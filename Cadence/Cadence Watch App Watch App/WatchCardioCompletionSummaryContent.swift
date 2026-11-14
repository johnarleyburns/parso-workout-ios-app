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
        let now = Date()
        let samples = WatchWorkoutHistorySummary.normalized(summary.hrSamples)
        let shared = WatchWorkoutSummaryPresentation.make(
            summary: WatchWorkoutHistorySummary(
                id: UUID(), kind: .cardio, title: "", start: now.addingTimeInterval(-summary.duration), end: now,
                hrSamples: samples, averageBPM: summary.avgHR, maximumBPM: summary.maxHR,
                minuteSummary: WatchStrengthHRCoverage.summary(
                    samples: samples, duration: summary.duration, profile: profile)),
            unit: .kilograms, isHistorical: false)
        VStack(spacing: 8) {
            row(durationLabel, Self.formatTime(summary.duration))
            WatchSummaryHeartRateBlock(presentation: shared, profile: profile)
                .padding(.horizontal, 20)
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
