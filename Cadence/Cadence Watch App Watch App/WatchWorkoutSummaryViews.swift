import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

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
                    Text(shown.text).font(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel(shown.accessibilityLabel)
                        .accessibilityIdentifier("watchSummary.hrCoverage")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(p.title).font(.headline)
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
                            Text(exercise.name).font(.footnote.weight(.semibold))
                            Text(exercise.setTexts.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
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
