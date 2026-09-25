import SwiftUI
import Charts
import CadenceCore
import CadenceFeatures

/// Fast, local-only controls for the Strength over time chart. The expensive
/// history projection is prepared by TrainingProgressView; changing this menu
/// only filters already-materialized series and never touches SwiftData.
struct ProgressStrengthChartView: View {
    let data: StrengthProgressChartData
    let unit: MeasurementUnitPreference
    @Binding var selectedNames: Set<String>

    private var selectedSeries: [E1RMSeries] {
        data.allSeries.filter { selectedNames.contains($0.exercise) }
    }

    var body: some View {
        if data.allSeries.allSatisfy({ $0.points.count < 2 }) {
            Text("Log a few weeks of working sets and your estimated-1RM trend appears here. e1RM is projected from the weight and reps of your heaviest sets.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            liftPicker
            Chart {
                ForEach(selectedSeries) { series in
                    ForEach(series.points) { point in
                        LineMark(x: .value("Week", point.weekStart),
                                 y: .value("e1RM", WorkoutMath.display(point.e1rm, in: unit)))
                            .foregroundStyle(by: .value("Lift", series.exercise))
                            .interpolationMethod(.catmullRom)
                    }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 175)
            .accessibilityElement()
            .accessibilityLabel("Estimated 1RM trend, last 12 weeks")
            .accessibilityValue(accessibilitySummary)

            VStack(spacing: 5) {
                ForEach(selectedSeries) { series in
                    HStack(spacing: 8) {
                        Text(series.exercise)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Text(series.points.isEmpty
                             ? "—"
                             : Format.weight(series.current, unit: unit, decimals: 0))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        trendTag(series.trend, delta: series.delta)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(series.exercise): \(Format.weight(series.current, unit: unit, decimals: 0)), \(trendLabel(series.trend, delta: series.delta))")
                }
            }
            .padding(.top, 8)
        }
    }

    private var liftPicker: some View {
        Menu {
            ForEach(data.exerciseNames, id: \.self) { name in
                toggleButton(name)
            }
        } label: {
            HStack(spacing: 6) {
                Text("Charted lifts")
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tint)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Choose lifts to chart")
        .accessibilityHint("Select Bench Press, Squat, Deadlift, or Combined")
        .accessibilityIdentifier("progress.strength.liftPicker")
    }

    @ViewBuilder
    private func toggleButton(_ name: String) -> some View {
        Button {
            if selectedNames.contains(name) {
                selectedNames.remove(name)
            } else {
                selectedNames.insert(name)
            }
        } label: {
            if selectedNames.contains(name) {
                Label(name, systemImage: "checkmark")
            } else {
                Text(name)
            }
        }
        .accessibilityIdentifier("progress.strength.lift.\(name.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }

    private var accessibilitySummary: String {
        let names = selectedSeries.map(\.exercise)
        return names.isEmpty ? "No lifts selected." : names.joined(separator: ", ")
    }

    private func trendLabel(_ trend: TrendDirection, delta: Double) -> String {
        ProgressPresenter.trendLabel(trend, delta: delta, unit: unit)
    }

    @ViewBuilder
    private func trendTag(_ trend: TrendDirection, delta: Double) -> some View {
        switch trend {
        case .rising:
            Label("+" + Format.weight(abs(delta), unit: unit, decimals: 0), systemImage: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.green)
        case .declining:
            Label("−" + Format.weight(abs(delta), unit: unit, decimals: 0), systemImage: "arrow.down.right")
                .font(.caption)
                .foregroundStyle(.orange)
        case .flat:
            Label("flat", systemImage: "minus")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
