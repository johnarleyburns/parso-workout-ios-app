import Foundation
import CadenceCore

public enum TodayLogHelper {
    public static func completedStrength(
        sessions: [WorkoutSession], now: Date = Date(), calendar: Calendar = .current
    ) -> (hasStrength: Bool, exerciseNames: [String]) {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        let completed = sessions.filter {
            $0.deletedAt == nil && !$0.isLogged && $0.endedAt != nil
            && $0.date >= today && $0.date < end
        }
        var seen = Set<String>()
        var names: [String] = []
        for s in completed.sorted(by: { ($0.endedAt ?? $0.date) > ($1.endedAt ?? $1.date) }) {
            for ex in s.exercisesInOrder where seen.insert(ex.name).inserted { names.append(ex.name) }
        }
        return (!completed.isEmpty, names)
    }
}
