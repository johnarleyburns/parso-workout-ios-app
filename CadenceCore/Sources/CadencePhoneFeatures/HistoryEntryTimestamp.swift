import CadenceCore
import Foundation

/// The "when" label for a Workouts History row: a weekday abbreviation for a
/// workout within the current training week ("Mon"), or the date otherwise
/// ("Nov 3"), always followed by a locale-correct time (12- or 24-hour,
/// matching the device's clock setting, same pattern as `WallClockLabel`).
public enum HistoryEntryTimestamp {
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f
    }()

    public static func format(_ date: Date, now: Date = Date()) -> String {
        let weekStart = WeeklyStats.weekStart(now: now)
        let datePart = date >= weekStart
            ? weekdayFormatter.string(from: date)
            : dateFormatter.string(from: date)
        return "\(datePart) · \(timeFormatter.string(from: date))"
    }
}
