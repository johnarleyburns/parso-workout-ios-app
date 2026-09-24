import SwiftUI
import SwiftData
import Charts
import CadenceCore
import CadenceFeatures

/// The Progress tab's personal-record timeline (FR-5.2, revenue plan Phase 6).
/// Renders the all-time PR progression per lift plus a "trophy shelf" of the most
/// recent records — each shareable as a branded PNG through `ShareCardRenderer`.
struct PRTimelineView: View {
    @Environment(AppSettings.self) private var settings
    let sessions: [WorkoutSession]
    @State private var selectedExerciseName: String?

    private var events: [PREvent] {
        WorkoutRepository.prEvents(from: sessions, rule: settings.prRule, formula: settings.formula)
    }
    private var rows: [PRTimelinePresenter.Row] {
        PRTimelinePresenter.rows(events: events, unit: settings.unit)
    }
    private var exerciseNames: [String] {
        Set(events.map(\.exerciseName)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
    private var selectedName: String? {
        guard !exerciseNames.isEmpty else { return nil }
        if let selectedExerciseName, exerciseNames.contains(selectedExerciseName) {
            return selectedExerciseName
        }
        return exerciseNames.first
    }
    private var selectedEvents: [PREvent] {
        guard let selectedName else { return [] }
        return events.filter { $0.exerciseName == selectedName }
    }
    private var selectedRows: [PRTimelinePresenter.Row] {
        rows.filter { $0.exerciseName == selectedName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Personal records")
                .font(.headline)
            Text("all-time bests \u{00b7} \(settings.prRule.displayName.lowercased())")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)

            if rows.isEmpty {
                Text("Log working sets and every time you beat an all-time best it lands here \u{2014} ready to share.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                exercisePicker
                chart
                Divider().padding(.vertical, 10)
                VStack(spacing: 0) {
                    ForEach(Array(selectedRows.prefix(8).enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 { Divider() }
                        prRow(row, event: selectedEvents.first { $0.id == row.id })
                    }
                }
            }
            Divider().padding(.top, 12).padding(.bottom, 8)
            CitationLink(citation: CitationRegistry.oneRMEstimation,
                         context: "How PRs & estimated 1RM are computed", compact: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .yellow)
        .accessibilityIdentifier("progress.prTimeline")
    }

    private var exercisePicker: some View {
        Picker("Exercise personal record", selection: Binding(
            get: { selectedName ?? "" },
            set: { selectedExerciseName = $0 })) {
            ForEach(exerciseNames, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("progress.personalRecords.exercisePicker")
        .accessibilityLabel("Choose exercise personal record")
    }

    @ViewBuilder private var chart: some View {
        let series = selectedEvents.map { (name: $0.exerciseName, date: $0.date,
                                   value: WorkoutMath.display($0.value, in: settings.unit)) }
        Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Date", p.date), y: .value("PR", p.value))
                    .interpolationMethod(.stepEnd)
                PointMark(x: .value("Date", p.date), y: .value("PR", p.value))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartPlotStyle { $0.frame(height: 160) }
        .accessibilityElement()
        .accessibilityLabel("\(selectedName ?? "Exercise") personal-record progression")
        .accessibilityValue("\(selectedEvents.count) records")
    }

    @ViewBuilder private func prRow(_ row: PRTimelinePresenter.Row, event: PREvent?) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.exerciseName).font(.subheadline)
                Text(row.deltaLabel ?? "first-ever record")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(row.valueLabel).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(row.dateLabel).font(.caption2).foregroundStyle(.tertiary)
            }
            if let event, let url = shareURL(for: event) {
                ShareLink(item: url, preview: SharePreview("\(row.exerciseName) PR")) {
                    Image(systemName: "square.and.arrow.up").font(.callout)
                }
                .accessibilityLabel("Share \(row.exerciseName) personal record")
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.exerciseName), \(row.valueLabel), \(row.deltaLabel ?? "first-ever record")")
    }

    @MainActor private func shareURL(for event: PREvent) -> URL? {
        ShareCardRenderer.render(event: event, unit: settings.unit)
    }
}
