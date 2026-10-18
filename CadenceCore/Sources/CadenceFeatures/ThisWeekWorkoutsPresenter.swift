import Foundation
import CadenceCore

/// Logic for the This Week "My Workouts" section and the Today week-card
/// planned/done line. Views render these values; they never compute them.
public enum ThisWeekWorkoutsPresenter {

    /// Planned (not done, not cancelled) workouts dated inside the training week.
    public static func plannedThisWeek(_ items: [PlannedWorkoutsPresenter.Item],
                                       now: Date = Date(),
                                       calendar: Calendar = .current) -> [PlannedWorkoutsPresenter.Item] {
        let start = WeeklyStats.weekStart(now: now)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
        return items
            .filter { $0.date >= start && $0.date < end
                && $0.status != .cancelled && $0.status != .completed }
            .sorted { $0.date != $1.date ? $0.date < $1.date
                : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Unfinished (paused / in-progress) strength sessions started this week.
    public static func inProgressThisWeek(sessions: [WorkoutSession],
                                          now: Date = Date(),
                                          calendar: Calendar = .current) -> [WorkoutSession] {
        let start = WeeklyStats.weekStart(now: now)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
        return sessions
            .filter { $0.isResumable && $0.date >= start && $0.date < end }
            .sorted { $0.date > $1.date }
    }

    /// "M workouts planned, N workouts done" and its zero-count variants.
    public static func summary(planned: Int, done: Int) -> String {
        switch (planned > 0, done > 0) {
        case (true, true):
            return String(localized: "\(planned) workouts planned, \(done) workouts done", bundle: .module)
        case (true, false):
            return String(localized: "\(planned) workouts planned", bundle: .module)
        case (false, true):
            return String(localized: "\(done) workouts done", bundle: .module)
        case (false, false):
            return String(localized: "No workouts planned or done", bundle: .module)
        }
    }
}
