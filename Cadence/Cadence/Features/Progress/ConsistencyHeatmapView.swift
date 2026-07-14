import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// The Progress tab's training-consistency heatmap (FR-5.4, revenue plan Phase 6):
/// a GitHub-style calendar of trained vs rest days over the trailing weeks, plus a
/// streak headline. All bucketing is pure (`ConsistencyHeatmap`); this view only
/// maps the semantic `Shade` to a colour ramp.
struct ConsistencyHeatmapView: View {
    let sessions: [WorkoutSession]
    var weeks: Int = 17
    var calendar: Calendar = .current

    private var display: ConsistencyHeatmapPresenter.Display {
        let now = Date()
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        // Start on the Sunday/Monday boundary `weeks` back so columns align to weeks.
        let rawStart = calendar.date(byAdding: .day, value: -7 * weeks, to: end) ?? end
        let start = startOfWeek(for: rawStart)
        let dates = sessions.filter { $0.deletedAt == nil }.map(\.date)
        return ConsistencyHeatmapPresenter.display(
            sessionDates: dates,
            range: DateInterval(start: start, end: end),
            calendar: calendar)
    }

    var body: some View {
        let d = display
        VStack(alignment: .leading, spacing: 0) {
            Text("Consistency")
                .font(.headline)
            Text(d.summary)
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)

            if d.trainedDays == 0 {
                Text("Your training days fill in here \u{2014} the more you show up, the deeper the streak.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                grid(cells: d.cells)
                legend.padding(.top, 10)
            }
            Divider().padding(.top, 12).padding(.bottom, 8)
            CitationLink(citation: CitationRegistry.frequencyMeta,
                         context: "Why weekly training frequency matters", compact: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: .green)
        .accessibilityIdentifier("progress.consistencyHeatmap")
    }

    /// Column-major grid: each column is a week (7 rows Sun→Sat).
    @ViewBuilder private func grid(cells: [ConsistencyHeatmapPresenter.Cell]) -> some View {
        let columns = stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)])
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 3) {
                        ForEach(week) { cell in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color(for: cell.shade))
                                .frame(width: 13, height: 13)
                                .accessibilityLabel(cell.accessibilityLabel)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less").font(.caption2).foregroundStyle(.tertiary)
            ForEach(ConsistencyHeatmapPresenter.Shade.allCases, id: \.rawValue) { shade in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color(for: shade))
                    .frame(width: 11, height: 11)
            }
            Text("More").font(.caption2).foregroundStyle(.tertiary)
        }
        .accessibilityHidden(true)
    }

    private func color(for shade: ConsistencyHeatmapPresenter.Shade) -> Color {
        switch shade {
        case .none:   return Color.green.opacity(0.10)
        case .light:  return Color.green.opacity(0.30)
        case .medium: return Color.green.opacity(0.50)
        case .strong: return Color.green.opacity(0.72)
        case .peak:   return Color.green
        }
    }

    private func startOfWeek(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}
