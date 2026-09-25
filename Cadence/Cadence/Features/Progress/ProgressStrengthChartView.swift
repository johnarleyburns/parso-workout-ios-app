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
    @State private var selectedDate: Date?

    private var selectedSeries: [E1RMSeries] {
        data.allSeries.filter { selectedNames.contains($0.exercise) }
    }

    private var defaultNames: Set<String> { ProgressStrengthSelection.defaultNames }

    private var customNames: [String] {
        data.exerciseNames.filter { !defaultNames.contains($0) }
    }

    var body: some View {
        if data.allSeries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                liftPicker
                Text("Log a few weeks of working sets and your estimated-1RM trend appears here. e1RM is projected from the weight and reps of your heaviest sets.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            liftPicker
            Chart {
                ForEach(selectedSeries) { series in
                    ForEach(series.points) { point in
                        LineMark(x: .value("Week", point.weekStart),
                                 y: .value("e1RM", WorkoutMath.display(point.e1rm, in: unit)))
                            .foregroundStyle(by: .value("Lift", series.exercise))
                            .interpolationMethod(.linear)
                        PointMark(x: .value("Week", point.weekStart),
                                  y: .value("e1RM", WorkoutMath.display(point.e1rm, in: unit)))
                            .foregroundStyle(by: .value("Lift", series.exercise))
                            .symbolSize(series.points.last?.id == point.id ? 65 : 28)
                            .annotation(position: .top, spacing: 3) {
                                if series.points.last?.id == point.id {
                                    Text(Format.weight(point.e1rm, unit: unit, decimals: 0))
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.primary)
                                }
                            }
                    }
                }
            }
            .chartForegroundStyleScale(range: [CadenceTheme.accent, CadenceTheme.link,
                                                CadenceTheme.attention, .purple])
            .chartXSelection(value: $selectedDate)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 175)
            .accessibilityElement()
            .accessibilityLabel("Estimated 1RM trend, last 12 weeks")
            .accessibilityValue(accessibilitySummary)

            if let selectionText {
                Text(selectionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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

            ForEach(data.emptyLifts, id: \.self) { name in
                HStack(spacing: 8) {
                    Image(systemName: "circle.dashed")
                        .foregroundStyle(CadenceTheme.attention)
                    Text("\(name) · no sessions yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add") {}
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(CadenceTheme.link)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(name), no sessions yet, Add")
            }
        }
    }

    private var liftPicker: some View {
        Menu {
            Section("Default lifts") {
                ForEach(data.exerciseNames.filter { defaultNames.contains($0) }, id: \.self) { name in
                    toggleButton(name)
                }
            }
            if !customNames.isEmpty {
                Section("Custom lifts") {
                    ForEach(customNames, id: \.self) { name in
                        toggleButton(name)
                    }
                }
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
        .accessibilityHint("Select one or more default or custom lifts")
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

    private var selectionText: String? {
        guard let selectedDate else { return nil }
        let points = selectedSeries.flatMap { series in
            series.points.map { (series.exercise, $0) }
        }
        guard let nearest = points.min(by: {
            abs($0.1.weekStart.timeIntervalSince(selectedDate)) < abs($1.1.weekStart.timeIntervalSince(selectedDate))
        }) else { return nil }
        return "\(nearest.0) · \(nearest.1.weekStart.formatted(date: .abbreviated, time: .omitted)) · \(Format.weight(nearest.1.e1rm, unit: unit, decimals: 0))"
    }

    private func trendLabel(_ trend: TrendDirection, delta: Double) -> String {
        ProgressPresenter.trendLabel(trend, delta: delta, unit: unit)
    }

    @ViewBuilder
    private func trendTag(_ trend: TrendDirection, delta: Double) -> some View {
        switch trend {
        case .rising:
            HStack(spacing: 6) {
                Label("PR", systemImage: "trophy.fill")
                    .foregroundStyle(CadenceTheme.achievement)
                Label("+" + Format.weight(abs(delta), unit: unit, decimals: 0), systemImage: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
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
