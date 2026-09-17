import Foundation
import CadenceCore

public enum PlannedWorkoutsPresenter {
    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let date: Date
        public let title: String
        public let detail: String
        public let status: ScheduledWorkoutStatus

        public init(id: UUID, date: Date, title: String, detail: String,
                    status: ScheduledWorkoutStatus) {
            self.id = id
            self.date = date
            self.title = title
            self.detail = detail
            self.status = status
        }
    }

    public static func today(_ items: [Item], now: Date = Date(),
                             calendar: Calendar = .current) -> [Item] {
        items.filter { calendar.isDate($0.date, inSameDayAs: now) && visible($0) }
            .sorted(by: order)
    }

    public static func todayAndFuture(_ items: [Item], now: Date = Date(),
                                      calendar: Calendar = .current) -> [Item] {
        let start = calendar.startOfDay(for: now)
        return items.filter { $0.date >= start && visible($0) }.sorted(by: order)
    }

    public static func overdue(_ items: [Item], now: Date = Date(),
                               calendar: Calendar = .current) -> [Item] {
        let start = calendar.startOfDay(for: now)
        return items.filter { $0.date < start && visible($0) }.sorted(by: order)
    }

    public static func showsMore(_ items: [Item], now: Date = Date(),
                                 calendar: Calendar = .current) -> Bool {
        !todayAndFuture(items, now: now, calendar: calendar).isEmpty
            || !overdue(items, now: now, calendar: calendar).isEmpty
    }

    private static func visible(_ item: Item) -> Bool {
        item.status != .cancelled && item.status != .completed
    }

    private static func order(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}
