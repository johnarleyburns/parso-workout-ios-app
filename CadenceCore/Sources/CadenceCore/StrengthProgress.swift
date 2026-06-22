import Foundation

/// One lift's estimated-1RM trajectory, bucketed by ISO week — the series behind
/// the Progress "Strength over time" chart. e1RM is an *estimate* (LeSuer et al.,
/// 1997); a ±2% week-over-week band is the noise floor (matches the trend epsilon
/// in `TrainingFacts`), so small wobbles read flat. Pure + `swift test`-able.
public struct E1RMPoint: Sendable, Equatable, Identifiable {
    public let weekStart: Date
    public let e1rm: Double            // best estimated 1RM that week (kg)
    public init(weekStart: Date, e1rm: Double) { self.weekStart = weekStart; self.e1rm = e1rm }
    public var id: Date { weekStart }
}

public struct E1RMSeries: Sendable, Equatable, Identifiable {
    public let exercise: String
    public let points: [E1RMPoint]     // chronological
    public init(exercise: String, points: [E1RMPoint]) { self.exercise = exercise; self.points = points }
    public var id: String { exercise }
    public var current: Double { points.last?.e1rm ?? 0 }
    public var baseline: Double { points.first?.e1rm ?? 0 }
    public var delta: Double { current - baseline }
    /// ±2% noise floor vs the first point → rising / flat / declining.
    public var trend: TrendDirection {
        guard baseline > 0, points.count >= 2 else { return .flat }
        let r = current / baseline
        if r > 1.02 { return .rising }
        if r < 0.98 { return .declining }
        return .flat
    }
}

public enum StrengthProgress {
    /// Best estimated 1RM per ISO week for the `topN` lifts with the most working
    /// sets over `weeks`. Pass the `@Query` sessions straight in.
    public static func series(from sessions: [WorkoutSession],
                              now: Date = Date(),
                              weeks: Int = 12,
                              topN: Int = 3,
                              formula: OneRepMaxFormula = .epley,
                              calendar: Calendar = .current) -> [E1RMSeries] {
        let windowStart = calendar.date(byAdding: .day, value: -7 * weeks, to: now) ?? now
        var byLift: [String: [Date: Double]] = [:]
        var setCount: [String: Int] = [:]
        for s in sessions where s.deletedAt == nil && s.date >= windowStart && s.date <= now {
            let week = calendar.dateInterval(of: .weekOfYear, for: s.date)?.start
                ?? calendar.startOfDay(for: s.date)
            for set in s.orderedSets where !set.isWarmup && set.isOwnerSet && set.reps > 0 && set.weight > 0 {
                guard let name = set.exercise?.name, !name.isEmpty else { continue }
                let e = WorkoutMath.estimated1RM(weight: set.weight, reps: set.reps, formula: formula)
                byLift[name, default: [:]][week] = max(byLift[name, default: [:]][week] ?? 0, e)
                setCount[name, default: 0] += 1
            }
        }
        let topLifts = setCount.sorted { $0.value > $1.value }.prefix(topN).map(\.key)
        return topLifts.compactMap { name -> E1RMSeries? in
            guard let weeks = byLift[name], !weeks.isEmpty else { return nil }
            let pts = weeks.sorted { $0.key < $1.key }.map { E1RMPoint(weekStart: $0.key, e1rm: $0.value) }
            return E1RMSeries(exercise: name, points: pts)
        }
        .sorted { $0.current > $1.current }
    }
}
