import SwiftUI
import Charts
import Accessibility
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// Fast, local-only controls for the Strength over time chart. The expensive
/// history projection is prepared by TrainingProgressView; changing this menu
/// only filters already-materialized series and never touches SwiftData.
struct ProgressStrengthChartView: View {
    let data: StrengthProgressChartData
    let unit: MeasurementUnitPreference
    @Binding var selectedNames: Set<String>
    let onAddLift: (String) -> Void
    @State private var selectedDate: Date?
    @State private var showInfo = false
    @Environment(AppSettings.self) private var settings

    /// The individual lifts the user has charted. The aggregate total is never
    /// taken from the precomputed data; it is recomputed from exactly these.
    private var chartedLiftSeries: [E1RMSeries] {
        data.allSeries.filter {
            $0.exercise != StrengthProgress.totalSeriesName && selectedNames.contains($0.exercise)
        }
    }

    private var selectedSeries: [E1RMSeries] {
        var series = chartedLiftSeries
        if selectedNames.contains(StrengthProgress.totalSeriesName) {
            let total = StrengthProgress.totalSeries(from: chartedLiftSeries)
            if !total.points.isEmpty { series.append(total) }
        }
        return series
    }

    private var defaultNames: Set<String> { ProgressStrengthSelection.defaultNames }

    private var customNames: [String] {
        data.exerciseNames.filter { !defaultNames.contains($0) }
    }

    var body: some View {
        content
            .sheet(isPresented: $showInfo) { infoSheet }
    }

    @ViewBuilder
    private var content: some View {
        if data.allSeries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                liftHeader
                Text("Log a few weeks of working sets and your estimated-1RM trend appears here. e1RM is projected from the weight and reps of your heaviest sets.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            liftHeader
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
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedDate)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 175)
            .accessibilityChartDescriptor(ProgressChartAccessibility(data: selectedSeries,
                                                                      unit: unit))
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
                HStack(spacing: 8) {
                    Text("Lift").frame(maxWidth: .infinity, alignment: .leading)
                    Text("e1RM").frame(minWidth: 88, alignment: .trailing)
                    Text("Trend").frame(minWidth: 82, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
                ForEach(selectedSeries) { series in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(seriesColor(for: series.exercise))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(series.exercise)
                            .font(.subheadline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(series.points.isEmpty
                             ? "—"
                             : Format.weight(series.current, unit: unit, decimals: 0))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .frame(minWidth: 88, alignment: .trailing)
                        trendTag(series.trend, delta: series.delta)
                            .frame(minWidth: 82, alignment: .trailing)
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
                    Button("Add") { onAddLift(name) }
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
                Image(systemName: "dumbbell.fill")
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

    /// Icon-only picker on the left, method details behind one info button on
    /// the right. The explanation and citation no longer take card space.
    private var liftHeader: some View {
        HStack(spacing: 8) {
            liftPicker
            Spacer(minLength: 0)
            Button { showInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About estimated 1RM trends")
            .accessibilityIdentifier("progress.strength.info")
        }
    }

    private var infoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Estimated 1RM trends use the \(settings.formula.displayName) formula selected in Settings, over the last 12 weeks.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    CitationLink(citation: CitationRegistry.oneRMEstimation, compact: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Estimated 1RM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showInfo = false }
                }
            }
        }
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
        return names.isEmpty ? String(localized: "No lifts selected.") : names.joined(separator: ", ")
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

    private func seriesColor(for exercise: String) -> Color {
        let colors: [Color] = [CadenceTheme.accent, CadenceTheme.link,
                               CadenceTheme.attention, .purple]
        let index = data.allSeries.firstIndex { $0.exercise == exercise } ?? 0
        return colors[index % colors.count]
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
                .foregroundStyle(.secondary)
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

private struct ProgressChartAccessibility: AXChartDescriptorRepresentable {
    let data: [E1RMSeries]
    let unit: MeasurementUnitPreference

    func makeChartDescriptor() -> AXChartDescriptor {
        let categories = data.flatMap { $0.points.map { $0.weekStart.formatted(date: .abbreviated, time: .omitted) } }
        let values = data.flatMap { $0.points.map { WorkoutMath.display($0.e1rm, in: unit) } }
        let lower = max(0, (values.min() ?? 0) * 0.9)
        let upper = max(lower + 1, (values.max() ?? 1) * 1.1)
        let xAxis = AXCategoricalDataAxisDescriptor(title: String(localized: "Week"), categoryOrder: categories)
        let yAxis = AXNumericDataAxisDescriptor(title: String(localized: "Estimated 1RM"),
                                                 range: lower...upper,
                                                 gridlinePositions: [],
                                                 valueDescriptionProvider: { value in
                                                     Format.weight(value, unit: unit)
                                                 })
        let series = data.map { item in
            AXDataSeriesDescriptor(name: item.exercise, isContinuous: true,
                                   dataPoints: item.points.map { point in
                                       AXDataPoint(x: point.weekStart.formatted(date: .abbreviated,
                                                                                  time: .omitted),
                                                   y: WorkoutMath.display(point.e1rm, in: unit))
                                   })
        }
        return AXChartDescriptor(title: String(localized: "Estimated 1RM trend"),
                                 summary: ProgressPresenter.strengthTrendSummary(series: data,
                                                                                   unit: unit),
                                 xAxis: xAxis, yAxis: yAxis, series: series)
    }
}
