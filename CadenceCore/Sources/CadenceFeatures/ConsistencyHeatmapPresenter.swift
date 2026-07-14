import Foundation
import CadenceCore

/// Prepares the Progress tab's consistency heatmap for rendering (FR-5.4). Pure
/// and headless: the intensity → colour mapping is a semantic enum, so the view
/// owns `Color` and `CadenceFeatures` stays SwiftUI-free.
public enum ConsistencyHeatmapPresenter {

    /// A semantic shade for one heatmap cell; the view maps it to a `Color` ramp.
    public enum Shade: Int, Equatable, Sendable, CaseIterable {
        case none = 0    // no training that day
        case light = 1
        case medium = 2
        case strong = 3
        case peak = 4
    }

    public struct Cell: Equatable, Identifiable {
        public let date: Date
        public let sessionCount: Int
        public let shade: Shade
        public let accessibilityLabel: String

        public init(date: Date, sessionCount: Int, shade: Shade, accessibilityLabel: String) {
            self.date = date
            self.sessionCount = sessionCount
            self.shade = shade
            self.accessibilityLabel = accessibilityLabel
        }

        public var id: Date { date }
    }

    public struct Display: Equatable {
        public let cells: [Cell]
        public let currentStreak: Int
        public let longestStreak: Int
        public let trainedDays: Int
        /// "12 days trained · 4-day streak" — the headline over the grid.
        public let summary: String

        public init(cells: [Cell], currentStreak: Int, longestStreak: Int,
                    trainedDays: Int, summary: String) {
            self.cells = cells
            self.currentStreak = currentStreak
            self.longestStreak = longestStreak
            self.trainedDays = trainedDays
            self.summary = summary
        }
    }

    public static func display(sessionDates: [Date],
                               range: DateInterval,
                               calendar: Calendar = .current) -> Display {
        let days = ConsistencyHeatmap.days(sessionDates: sessionDates, range: range, calendar: calendar)
        let cells = days.map { cell(for: $0, calendar: calendar) }
        let current = ConsistencyHeatmap.currentStreak(days: days)
        let longest = ConsistencyHeatmap.longestStreak(days: days)
        let trained = days.filter { $0.sessionCount > 0 }.count
        return Display(cells: cells,
                       currentStreak: current,
                       longestStreak: longest,
                       trainedDays: trained,
                       summary: summary(trainedDays: trained, currentStreak: current))
    }

    static func summary(trainedDays: Int, currentStreak: Int) -> String {
        let dayWord = trainedDays == 1 ? "day" : "days"
        let base = "\(trainedDays) \(dayWord) trained"
        guard currentStreak >= 2 else { return base }
        return "\(base) \u{00b7} \(currentStreak)-day streak"
    }

    static func cell(for day: HeatmapDay, calendar: Calendar) -> Cell {
        let shade = Shade(rawValue: max(0, min(4, day.intensity))) ?? .none
        return Cell(date: day.date,
                    sessionCount: day.sessionCount,
                    shade: shade,
                    accessibilityLabel: accessibilityLabel(for: day, calendar: calendar))
    }

    static func accessibilityLabel(for day: HeatmapDay, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let dateStr = f.string(from: day.date)
        switch day.sessionCount {
        case 0: return "\(dateStr): rest day"
        case 1: return "\(dateStr): 1 session"
        default: return "\(dateStr): \(day.sessionCount) sessions"
        }
    }
}
