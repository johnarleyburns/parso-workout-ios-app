import Foundation

/// One calendar day on the training-consistency heatmap (FR-5.4). Pure; the
/// colour comes from a semantic `intensity` bucket so `CadenceFeatures` and the
/// view stay free of `Color`.
public struct HeatmapDay: Sendable, Equatable, Identifiable {
    public let date: Date          // start-of-day in the supplied calendar
    public let sessionCount: Int
    public let intensity: Int      // 0…4, the colour ramp bucket

    public init(date: Date, sessionCount: Int, intensity: Int) {
        self.date = date
        self.sessionCount = sessionCount
        self.intensity = intensity
    }

    public var id: Date { date }
}

/// Training-consistency heatmap math. Buckets session dates into per-day counts
/// across a range. `Calendar` is a parameter (never `.current` inside) so DST
/// and timezone behaviour is deterministic and testable.
public enum ConsistencyHeatmap {

    /// The colour-ramp bucket for a day's session count. 0 sessions → 0; then
    /// 1 → 1, 2 → 2, 3 → 3, 4+ → 4 (saturates).
    public static func intensity(forSessionCount count: Int) -> Int {
        max(0, min(4, count))
    }

    /// One `HeatmapDay` per calendar day in `range` (inclusive of the start day,
    /// exclusive of the end day — a half-open interval, matching `DateInterval`),
    /// each carrying that day's session count and intensity bucket. Days with no
    /// sessions are present with `sessionCount == 0` so the grid has no gaps.
    public static func days(sessionDates: [Date],
                            range: DateInterval,
                            calendar: Calendar) -> [HeatmapDay] {
        // Bucket sessions by start-of-day.
        var counts: [Date: Int] = [:]
        for d in sessionDates {
            let day = calendar.startOfDay(for: d)
            counts[day, default: 0] += 1
        }

        var out: [HeatmapDay] = []
        var cursor = calendar.startOfDay(for: range.start)
        let end = range.end
        // Walk day by day using the calendar so DST-shifted days advance by one
        // calendar day, not a fixed 86 400 s (the classic off-by-one bug).
        while cursor < end {
            let count = counts[cursor] ?? 0
            out.append(HeatmapDay(date: cursor, sessionCount: count,
                                  intensity: intensity(forSessionCount: count)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor),
                  next > cursor else { break }
            cursor = next
        }
        return out
    }

    /// Longest run of consecutive trained days ending on or before the range end
    /// — the "current streak" headline, computed off the same buckets.
    public static func currentStreak(days: [HeatmapDay]) -> Int {
        var streak = 0
        for day in days.reversed() {
            if day.sessionCount > 0 { streak += 1 } else { break }
        }
        return streak
    }

    /// Longest trained streak anywhere in the range.
    public static func longestStreak(days: [HeatmapDay]) -> Int {
        var best = 0, run = 0
        for day in days {
            if day.sessionCount > 0 { run += 1; best = max(best, run) } else { run = 0 }
        }
        return best
    }
}
