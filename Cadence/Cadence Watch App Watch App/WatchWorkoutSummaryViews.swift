import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Bound summary content to the visible Watch width before laying out charts
/// and text. Long labels must grow vertically, never widen the scroll content.
struct WatchSummaryScrollView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .containerRelativeFrame(.horizontal, alignment: .leading)
        }
    }
}

/// Keep compact metrics on one row when they fit; long translations and larger
/// text sizes put the value below its label instead of clipping either edge.
struct WatchSummaryMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                caption.fixedSize()
                Spacer(minLength: 0)
                metric.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                caption.fixedSize(horizontal: false, vertical: true)
                metric.fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
    }

    private var caption: some View {
        Text(label).font(.caption).foregroundStyle(.secondary)
    }

    private var metric: some View {
        Text(value).font(.system(.caption, design: .monospaced).bold()).monospacedDigit()
    }
}

/// Shared static HR content (chart, avg/max, credit rows, coverage) for completion and history.
struct WatchSummaryHeartRateBlock: View {
    let presentation: WatchWorkoutSummaryPresentation
    let profile: CardioIntensityProfile
    var storedSummary: CardioMinuteSummary?
    var pending = false

    var body: some View {
        if presentation.showsHeartRateChart {
            VStack(alignment: .leading, spacing: 4) {
                WatchHeartRateSection(hrSamples: presentation.hrSamples, intensityProfile: profile,
                                      sessionDuration: presentation.durationSeconds, storedSummary: storedSummary)
                if let coverage = presentation.coverage {
                    let shown = pending
                        ? WatchStrengthHRCoverage.presentation(
                            summary: storedSummary, sampleCount: presentation.hrSamples.count, pending: true)
                        : coverage
                    // Silence on success: only say something when there's a
                    // problem (partial/missing coverage) worth acting on.
                    if shown.kind != .complete {
                        Text(shown.text).font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(shown.accessibilityLabel)
                            .accessibilityIdentifier("watchSummary.hrCoverage")
                    }
                }
            }
        }
    }
}

/// Read-only summary of a completed workout from history. No receipts or completion actions.
struct WatchHistoricalWorkoutSummaryView: View {
    let summary: WatchWorkoutHistorySummary
    @Environment(AppSettings.self) private var watchSettings

    private var presentation: WatchWorkoutSummaryPresentation {
        WatchWorkoutSummaryPresentation.make(summary: summary, unit: watchSettings.unit, isHistorical: true)
    }

    var body: some View {
        let p = presentation
        WatchSummaryScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(p.title).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                (Text(p.start, format: .dateTime.month().day()) + Text(verbatim: " · \(Self.format(p.durationSeconds))"))
                    .font(.caption2).foregroundStyle(.secondary)
                if p.kind == .strength {
                    if let sets = p.workingSetCount {
                        (Text("\(sets) sets") + Text(verbatim: p.volumeText.map { " · \($0)" } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    if let meters = p.distanceMeters, meters > 0 {
                        let unit = watchSettings.distanceUnit
                        let value = unit == .miles ? meters / 1609.344 : meters / 1000
                        Text(verbatim: String(format: "%.2f %@", value, unit.abbreviation)).font(.caption2)
                    }
                    if let laps = p.laps { Text("Laps \(laps)").font(.caption2) }
                }
                WatchSummaryHeartRateBlock(presentation: p, profile: watchSettings.resolvedCardioIntensityProfile,
                                           storedSummary: summary.minuteSummary)
                if p.omissions.contains(.heartRate) {
                    Text("No heart rate was recorded for this workout.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if p.kind == .strength {
                    ForEach(Array(p.exercises.enumerated()), id: \.offset) { _, exercise in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name.localizedExerciseName).font(.footnote.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(exercise.setTexts.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .navigationTitle(p.title)
        .accessibilityIdentifier("watch.historySummary")
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Resolves a My Workouts row to its detail, loading the stored data it needs.
struct WatchMyWorkoutDestination: View {
    let row: WatchMyWorkoutRow
    let pendingCardioCompletions: [WatchCardioCompletion]
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var watchSettings

    var body: some View {
        switch WatchMyWorkoutRoute.route(for: row) {
        case .plannedDetail:
            WatchPlannedWorkoutDetailView(row: row)
        case .strengthSummary(let id):
            if let summary = strengthSummary(id) {
                WatchHistoricalWorkoutSummaryView(summary: summary)
            } else {
                WatchBasicWorkoutFallbackView(row: row)
            }
        case .cardioSummary(let id):
            if let summary = cardioSummary(id) {
                WatchHistoricalWorkoutSummaryView(summary: summary)
            } else {
                WatchBasicWorkoutFallbackView(row: row)
            }
        case .cardioFallback:
            WatchBasicWorkoutFallbackView(row: row)
        }
    }

    private func strengthSummary(_ id: UUID) -> WatchWorkoutHistorySummary? {
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        guard let session = (try? context.fetch(descriptor))?.first else { return nil }
        return .make(session: session, profile: watchSettings.resolvedCardioIntensityProfile)
    }

    private func cardioSummary(_ id: UUID) -> WatchWorkoutHistorySummary? {
        let descriptor = FetchDescriptor<WatchCardioHistoryRecord>(predicate: #Predicate { $0.id == id })
        if let data = (try? context.fetch(descriptor))?.first?.summaryData,
           let summary = WatchWorkoutHistorySummary.decode(data) { return summary }
        return pendingCardioCompletions.first { $0.id == id }.map {
            .make(completion: $0, profile: watchSettings.resolvedCardioIntensityProfile)
        }
    }
}

/// Lightweight planned-workout detail; never presented as a completed summary.
struct WatchPlannedWorkoutDetailView: View {
    let row: WatchMyWorkoutRow
    var body: some View {
        List {
            Text("Planned").font(.caption2.weight(.bold)).foregroundStyle(WatchTone.accent)
            ForEach(Array(row.exerciseNames.enumerated()), id: \.offset) { _, name in
                Text(name).font(.footnote)
            }
        }
        .navigationTitle(row.title)
    }
}

/// Honest compact fallback for legacy rows with no rich snapshot: only the recorded basics.
struct WatchBasicWorkoutFallbackView: View {
    let row: WatchMyWorkoutRow
    @Environment(AppSettings.self) private var watchSettings
    var body: some View {
        List {
            if let date = row.date {
                Text(date, format: .dateTime.month().day().year()).font(.caption2).foregroundStyle(.secondary)
            }
            if row.showsSetCount { Text("\(row.setCount) sets").font(.footnote) }
            if let summary = row.cardioSummary(distanceUnit: watchSettings.distanceUnit) {
                Text(summary).font(.footnote)
            }
            if let origin = row.originLabel {
                Text(origin).font(.caption2).foregroundStyle(.secondary)
            }
            Text("Heart rate and detail were not saved for this workout.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .navigationTitle(row.title)
    }
}
