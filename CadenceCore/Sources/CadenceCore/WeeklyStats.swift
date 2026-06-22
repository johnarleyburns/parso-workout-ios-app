import Foundation

/// Pure aggregates for Home's weekly tiles (feedback batch 3): cardio minutes,
/// strength volume, and body-part coverage over the trailing 7 days. Operates on
/// the `@Model` rows directly (same module) so the view can pass its `@Query`
/// arrays straight in, and it stays `swift test`-able with an in-memory store.
public enum WeeklyStats {

    /// The most recent Monday at 00:00 local time (start of the training week).
    /// Weeks reset every Monday at midnight.
    public static func weekStart(now: Date = Date()) -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = 2  // Monday
        components.hour = 0
        components.minute = 0
        components.second = 0
        return cal.date(from: components) ?? now.addingTimeInterval(-7 * 86_400)
    }

    /// Σ of cardio workout durations (minutes) with `start >= since`.
    public static func cardioMinutes(_ cardio: [CardioWorkout], since: Date) -> Int {
        let secs = cardio.filter { $0.start >= since }.reduce(0.0) { $0 + $1.duration }
        return Int((secs / 60).rounded())
    }

    /// Σ owner working-set volume (kg) across sessions dated `>= since`. Mirrors
    /// `WorkoutSession.totalVolume` (owner, non-warmup); pure bodyweight sets
    /// (0 added load) contribute 0.
    public static func volumeKg(_ sessions: [WorkoutSession], since: Date) -> Double {
        sessions.filter { $0.date >= since }.reduce(0.0) { $0 + $1.totalVolume }
    }

    /// Body-part coverage from the week's strength sessions: every exercise the
    /// owner logged a set for (dated `>= since`), read by primary+secondary
    /// muscles. Returns parts hit + parts missing (canonical order).
    public static func bodyParts(_ sessions: [WorkoutSession], since: Date) -> (hit: Set<BodyPart>, missing: [BodyPart]) {
        var lists: [[String]] = []
        for session in sessions where session.date >= since {
            for ex in session.exercisesInOrder {
                guard session.orderedSets.contains(where: { $0.exercise?.id == ex.id && $0.isOwnerSet }) else { continue }
                lists.append(ex.primaryMuscles + ex.secondaryMuscles)
            }
        }
        return BodyPart.coverage(forMuscleLists: lists)
    }
}
