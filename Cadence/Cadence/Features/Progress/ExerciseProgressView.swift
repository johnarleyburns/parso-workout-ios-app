import SwiftUI
import Charts
import CadenceCore
import CadenceFeatures

/// A deliberately small exercise-level drill-down. The Progress tab remains
/// the overview; this view answers the common follow-up question without
/// making Home or Progress fetch another history projection.
struct ExerciseProgressView: View {
    let exercise: Exercise

    @Environment(AppSettings.self) private var settings

    private var points: [WorkoutRepository.TrendPoint] {
        WorkoutRepository.trendSeries(for: exercise,
                                      rule: settings.prRule,
                                      formula: settings.formula)
    }

    private var progressSummary: ExerciseProgressPresenter.Summary {
        ExerciseProgressPresenter.summary(points: points)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                if points.count >= 2 {
                    Chart {
                        ForEach(points) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value(settings.prRule.displayName, displayValue(point.value)))
                                .interpolationMethod(.catmullRom)
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value(settings.prRule.displayName, displayValue(point.value)))
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 220)
                    .accessibilityElement()
                    .accessibilityLabel("\(exercise.name) \(settings.prRule.displayName) trend")
                    .accessibilityValue(accessibilitySummary)
                } else {
                    ContentUnavailableView(
                        "Not enough history yet",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Log this exercise in at least two workouts to see a trend."))
                }
                Text("Working sets only · \(settings.prRule.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Exercise Progress")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("exercise.progress")
    }

    private var summary: some View {
        HStack(spacing: 10) {
            metric("Latest", value: progressSummary.latest.map {
                "\($0.date.formatted(date: .abbreviated, time: .omitted)) · \(displayText($0.value))"
            } ?? "—")
            metric("Best", value: progressSummary.best.map(displayText) ?? "—")
            metric("Sessions", value: String(progressSummary.sessionCount))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .blue)
        .accessibilityIdentifier("exercise.progress.summary")
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayValue(_ value: Double) -> Double {
        WorkoutMath.display(value, in: settings.unit)
    }

    private func displayText(_ value: Double) -> String {
        Format.weight(value, unit: settings.unit, decimals: 1)
    }

    private var accessibilitySummary: String {
        guard let latest = progressSummary.latest else { return "No logged history." }
        return "Latest \(displayText(latest.value)); best \(progressSummary.best.map(displayText) ?? "unknown"); \(progressSummary.sessionCount) training days."
    }
}
