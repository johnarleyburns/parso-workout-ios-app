import Foundation

/// Minimal immutable input to the Progress cardio trend, detached from SwiftData.
public struct CardioWorkoutDurationSample: Sendable, Equatable {
    public let start: Date
    public let end: Date?
    public let isDeleted: Bool

    public init(start: Date, end: Date?, isDeleted: Bool = false) {
        self.start = start
        self.end = end
        self.isDeleted = isDeleted
    }
}

public struct ProgressCardioWeekTotal: Sendable, Equatable, Identifiable {
    public let start: Date
    public let minutes: Double
    public var id: Date { start }

    public init(start: Date, minutes: Double) {
        self.start = start
        self.minutes = minutes
    }
}

/// Projects completed cardio durations into four Monday-starting local weeks.
public enum ProgressCardioTrendPresenter {
    public static func weeklyTotals(for workouts: [CardioWorkoutDurationSample],
                                    now: Date = Date(),
                                    timeZone: TimeZone = .current) -> [ProgressCardioWeekTotal] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let currentWeek = calendar.date(from: components) ?? now.addingTimeInterval(-7 * 86_400)

        return (0..<4).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let minutes = workouts.reduce(0.0) { total, workout in
                guard !workout.isDeleted,
                      workout.start >= start, workout.start < end,
                      let finish = workout.end else { return total }
                return total + max(0, finish.timeIntervalSince(workout.start)) / 60
            }
            return ProgressCardioWeekTotal(start: start, minutes: minutes)
        }
    }
}
