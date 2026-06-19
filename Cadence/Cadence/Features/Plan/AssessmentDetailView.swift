import SwiftUI
import SwiftData
import Charts
import CadenceCore

/// One assessment kind's screen (strength-pivot P4): the standardized protocol,
/// a "Record result" action, and — once there's history — a per-series trend
/// chart and the longitudinal log. Lift-specific kinds (e1RM / rep-max) can hold
/// several series at once (one per lift), each tracked separately.
struct AssessmentDetailView: View {
    let kind: AssessmentKind

    @Environment(AppSettings.self) private var settings
    @Query private var rows: [Assessment]
    @State private var recording = false

    init(kind: AssessmentKind) {
        self.kind = kind
        let raw = kind.rawValue
        _rows = Query(filter: #Predicate<Assessment> { $0.kind == raw },
                      sort: \Assessment.date, order: .forward)
    }

    /// Longitudinal summaries (one per series). Lift-specific kinds may yield more
    /// than one; bodyweight kinds yield at most one.
    private var summaries: [AssessmentSummary] {
        AssessmentMath.summaries(from: rows)
    }

    /// The raw results of a given series, oldest-first, for the chart + log.
    private func results(for summary: AssessmentSummary) -> [Assessment] {
        rows.filter { $0.seriesKey == summary.id }
    }

    var body: some View {
        List {
            Section("Protocol") {
                Text(kind.protocolText)
                    .font(.callout)
                    .accessibilityIdentifier("assessment.protocol")
            }

            if !kind.citationIds.isEmpty {
                Section("Evidence") {
                    ForEach(kind.citationIds.compactMap { CitationRegistry.citation(forId: $0) }, id: \.id) { citation in
                        CitationLink(citation: citation)
                    }
                }
            }

            if summaries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No results yet",
                        systemImage: kind.symbol,
                        description: Text("Record your first test to start a trend the coach can track."))
                        .accessibilityIdentifier("assessment.empty")
                }
            } else {
                ForEach(summaries) { summary in
                    series(summary)
                }
            }
        }
        .navigationTitle(kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    recording = true
                } label: {
                    Label("Record result", systemImage: "plus")
                }
                .accessibilityIdentifier("assessment.record")
            }
        }
        .sheet(isPresented: $recording) {
            RecordAssessmentView(kind: kind)
        }
    }

    // MARK: Per-series section

    @ViewBuilder
    private func series(_ summary: AssessmentSummary) -> some View {
        let history = results(for: summary)
        Section(AssessmentDisplay.seriesTitle(summary)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AssessmentDisplay.value(summary.latest, kind: kind, unit: settings.unit))
                            .font(.title3.weight(.semibold)).monospacedDigit()
                        Text("Latest · best \(AssessmentDisplay.value(summary.best, kind: kind, unit: settings.unit))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if summary.count >= 2 { TrendBadge(trend: summary.trend) }
                }

                if history.count >= 2 {
                    chart(history)
                        .frame(height: 160)
                        .accessibilityIdentifier("assessment.chart.\(summary.id)")
                }
            }
            .padding(.vertical, 4)

            ForEach(history.reversed()) { row in
                HStack {
                    Text(row.date, format: .dateTime.month().day().year())
                        .font(.subheadline)
                    Spacer()
                    Text(AssessmentDisplay.value(row.value, kind: kind, unit: settings.unit))
                        .font(.subheadline.weight(.medium)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func chart(_ history: [Assessment]) -> some View {
        Chart(history) { row in
            LineMark(x: .value("Date", row.date),
                     y: .value(kind.unit.rawValue, displayValue(row.value)))
                .foregroundStyle(.tint)
            PointMark(x: .value("Date", row.date),
                      y: .value(kind.unit.rawValue, displayValue(row.value)))
                .foregroundStyle(.tint)
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }

    /// Chart values follow the same display unit as the text: kg-tests convert to
    /// the user's preference; reps/seconds are unit-free.
    private func displayValue(_ value: Double) -> Double {
        kind.unit == .weightKg ? WorkoutMath.display(value, in: settings.unit) : value
    }
}
