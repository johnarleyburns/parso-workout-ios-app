import SwiftUI
import Charts
import CadenceCore

/// Per-exercise progress (FR-5.1, 5.2): a metric trend chart with PR markers and
/// the full set history.
struct ExerciseTrendView: View {
    let exercise: Exercise
    @Environment(AppSettings.self) private var settings
    @State private var rule: PRRule = .topWeight

    private var series: [WorkoutRepository.TrendPoint] {
        WorkoutRepository.trendSeries(for: exercise, rule: rule, formula: settings.formula)
    }
    private var prTimeline: [WorkoutRepository.TrendPoint] {
        WorkoutRepository.prTimeline(for: exercise, rule: rule, formula: settings.formula)
    }
    private var history: [SetEntry] {
        (exercise.sets ?? []).sorted { $0.completedAt > $1.completedAt }
    }

    var body: some View {
        List {
            Section {
                Picker("Metric", selection: $rule) {
                    ForEach(PRRule.allCases) { Text(shortName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("trend.metric")

                Chart {
                    ForEach(series) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Value", display(p.value)))
                            .interpolationMethod(.catmullRom)
                        AreaMark(x: .value("Date", p.date), y: .value("Value", display(p.value)))
                            .foregroundStyle(.tint.opacity(0.12))
                    }
                    ForEach(prTimeline) { p in
                        PointMark(x: .value("Date", p.date), y: .value("Value", display(p.value)))
                            .foregroundStyle(.orange)
                            .symbol(.diamond)
                    }
                }
                .frame(height: 200)
                .accessibilityIdentifier("trend.chart")
                .accessibilityLabel("\(exercise.name) \(shortName(rule)) trend")
            }

            if !prTimeline.isEmpty {
                Section("PR Timeline") {
                    ForEach(prTimeline.reversed()) { p in
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(.orange)
                            Text(Format.weight(p.value, unit: rule == .topVolume ? .kilograms : settings.unit))
                                .monospacedDigit()
                            Spacer()
                            Text(p.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("trend.prList")
            }

            Section("History") {
                ForEach(history) { set in
                    HStack {
                        Text(set.completedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(Format.setLine(set, unit: settings.unit)).monospacedDigit()
                        if set.isWarmup {
                            Text("warmup").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .accessibilityIdentifier("trend.history")
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func display(_ kg: Double) -> Double {
        rule == .topVolume ? kg : WorkoutMath.display(kg, in: settings.unit)
    }

    private func shortName(_ r: PRRule) -> String {
        switch r {
        case .topWeight: return "Top weight"
        case .estimated1RM: return "Est. 1RM"
        case .topVolume: return "Volume"
        }
    }
}
