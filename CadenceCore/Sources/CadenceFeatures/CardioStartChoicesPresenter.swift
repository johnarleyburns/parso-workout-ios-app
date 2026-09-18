import CadenceCore

/// Keeps the Start Workout cardio surface compact without hiding the full
/// taxonomy. Recent types win; the fallback trio fills unused slots for a new
/// user, then the remaining types are available behind Show more.
public enum CardioStartChoicesPresenter {
    public static let fallback: [WorkoutType] = [.run, .cycle, .swim]

    public static func initial(recent: [WorkoutType], all: [WorkoutType]) -> [WorkoutType] {
        var result: [WorkoutType] = []
        for type in recent + fallback where type != .weights && type != .other && all.contains(type) {
            if !result.contains(type) { result.append(type) }
            if result.count == 3 { break }
        }
        return result
    }

    public static func remaining(initial: [WorkoutType], all: [WorkoutType]) -> [WorkoutType] {
        all.filter { $0 != .weights && !initial.contains($0) }
    }
}
