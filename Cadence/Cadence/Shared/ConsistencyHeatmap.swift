import SwiftUI

/// A GitHub-style training-consistency grid (FR-5.4): one column per week, one
/// row per weekday, filled where a workout happened.
struct ConsistencyHeatmap: View {
    let trainingDays: Set<Date>
    var weeks: Int = 16
    private let calendar = Calendar.current

    var body: some View {
        let columns = buildColumns()
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { row in
                            let day = week[row]
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(for: day))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 12, height: 12)
                RoundedRectangle(cornerRadius: 3).fill(.green).frame(width: 12, height: 12)
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("trends.consistency")
        .accessibilityLabel("Training consistency, last \(weeks) weeks")
        .accessibilityValue("\(trainingDays.count) training days")
    }

    private func color(for day: Date?) -> Color {
        guard let day else { return .clear }
        return trainingDays.contains(calendar.startOfDay(for: day)) ? .green : Color(.quaternaryLabel)
    }

    /// Columns of 7 days each, oldest week first, aligned so the last column ends today.
    private func buildColumns() -> [[Date?]] {
        let today = calendar.startOfDay(for: Date())
        // Find the start of the current week (Sunday-ish per locale).
        let weekday = calendar.component(.weekday, from: today)
        let startOfThisWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: today)!
        var columns: [[Date?]] = []
        for w in stride(from: weeks - 1, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .day, value: -w * 7, to: startOfThisWeek) else { continue }
            var col: [Date?] = []
            for d in 0..<7 {
                let day = calendar.date(byAdding: .day, value: d, to: weekStart)!
                col.append(day <= today ? day : nil)
            }
            columns.append(col)
        }
        return columns
    }
}
