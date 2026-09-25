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

/// Sendable projection used to prepare Progress charts away from the UI actor.
/// SwiftData models stay on the model actor; only these small value rows cross
/// into the chart-preparation task.
public struct StrengthProgressSetInput: Sendable, Equatable {
    public let exerciseName: String
    public let completedAt: Date
    public let weightKg: Double
    public let reps: Int
    public let isWarmup: Bool
    public let isOwnerSet: Bool

    public init(exerciseName: String, completedAt: Date, weightKg: Double, reps: Int,
                isWarmup: Bool, isOwnerSet: Bool) {
        self.exerciseName = exerciseName
        self.completedAt = completedAt
        self.weightKg = weightKg
        self.reps = reps
        self.isWarmup = isWarmup
        self.isOwnerSet = isOwnerSet
    }
}

public struct StrengthProgressSessionInput: Sendable, Equatable {
    public let date: Date
    public let deleted: Bool
    public let sets: [StrengthProgressSetInput]

    public init(date: Date, deleted: Bool, sets: [StrengthProgressSetInput]) {
        self.date = date
        self.deleted = deleted
        self.sets = sets
    }
}

public struct StrengthProgressChartData: Sendable, Equatable {
    public let series: [E1RMSeries]
    public let emptyLifts: [String]

    public init(series: [E1RMSeries], emptyLifts: [String] = []) {
        self.series = series
        self.emptyLifts = emptyLifts
    }

    public var allSeries: [E1RMSeries] { series }

    public var exerciseNames: [String] {
        var names = series.map(\.exercise)
        // Combined remains a stable picker choice even when this window has
        // only custom lifts; it is not added to `series` unless it has points,
        // so an empty legend entry can never be rendered.
        if !names.contains("Combined") { names.append("Combined") }
        return names
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
        let inputs = sessions.map { session in
            StrengthProgressSessionInput(
                date: session.date,
                deleted: session.deletedAt != nil,
                sets: session.orderedSets.compactMap { set in
                    guard let name = set.exercise?.name, !name.isEmpty else { return nil }
                    return StrengthProgressSetInput(exerciseName: name,
                                                    completedAt: set.completedAt,
                                                    weightKg: set.effectiveLoadKg,
                                                    reps: set.reps,
                                                    isWarmup: set.isWarmup,
                                                    isOwnerSet: set.isOwnerSet)
                })
        }
        return seriesFromInputs(inputs, now: now, weeks: weeks, topN: topN,
                                formula: formula, calendar: calendar)
    }

    /// Pure chart preparation for use from a background task.
    private static func seriesFromInputs(_ sessions: [StrengthProgressSessionInput],
                                         now: Date = Date(),
                                         weeks: Int = 12,
                                         topN: Int = 3,
                                         formula: OneRepMaxFormula = .epley,
                                         calendar: Calendar = .current) -> [E1RMSeries] {
        let windowStart = calendar.date(byAdding: .day, value: -7 * weeks, to: now) ?? now
        var byLift: [String: [Date: Double]] = [:]
        var setCount: [String: Int] = [:]
        for session in sessions where !session.deleted && session.date >= windowStart && session.date <= now {
            let week = calendar.dateInterval(of: .weekOfYear, for: session.date)?.start
                ?? calendar.startOfDay(for: session.date)
            for set in session.sets where !set.isWarmup && set.isOwnerSet && set.reps > 0 && set.weightKg > 0 {
                let name = set.exerciseName
                let e = WorkoutMath.estimated1RM(weight: set.weightKg, reps: set.reps, formula: formula)
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

    /// The fixed series shown by Progress: Bench Press, Barbell Squat, Deadlift,
    /// and their week-by-week Combined total. Older history may use barbell or
    /// Back Squat aliases; those normalize into the fixed labels here. Other
    /// lifts remain available as selectable custom series.
    public static func chartData(from sessions: [StrengthProgressSessionInput],
                                 now: Date = Date(),
                                 weeks: Int = 12,
                                 formula: OneRepMaxFormula = .epley,
                                 calendar: Calendar = .current) -> StrengthProgressChartData {
        let all = seriesFromInputs(sessions, now: now, weeks: weeks, topN: .max,
                                   formula: formula, calendar: calendar)
        let aliases: [(String, Set<String>)] = [
            ("Bench Press", ["benchpress", "barbellbenchpress"]),
            ("Barbell Squat", ["squat", "backsquat", "barbellsquat"]),
            ("Deadlift", ["deadlift", "barbelldeadlift"])
        ]
        var pointsByLift: [String: [Date: Double]] = [:]
        for (label, names) in aliases {
            var points: [Date: Double] = [:]
            for item in all where names.contains(normalized(item.exercise)) {
                for point in item.points {
                    points[point.weekStart] = max(points[point.weekStart] ?? 0, point.e1rm)
                }
            }
            pointsByLift[label] = points
        }
        let fixedSeries = aliases.map { label, _ in
            E1RMSeries(exercise: label,
                       points: pointsByLift[label, default: [:]]
                           .sorted { $0.key < $1.key }
                           .map { E1RMPoint(weekStart: $0.key, e1rm: $0.value) })
        }
        let canonicalNames = Set(aliases.flatMap { $0.1 })
        let customSeries = all
            .filter { item in !canonicalNames.contains(normalized(item.exercise)) }
            .sorted { $0.exercise.localizedStandardCompare($1.exercise) == .orderedAscending }
        let weeksWithData = Set(pointsByLift.values.flatMap(\.keys)).sorted()
        let totalPoints = weeksWithData.compactMap { week -> E1RMPoint? in
            let total = aliases.reduce(0.0) { sum, entry in
                sum + (pointsByLift[entry.0]?[week] ?? 0)
            }
            return total > 0 ? E1RMPoint(weekStart: week, e1rm: total) : nil
        }
        let combined = E1RMSeries(exercise: "Combined", points: totalPoints)
        let nonEmptyFixed = fixedSeries.filter { !$0.points.isEmpty }
        let allSeries = nonEmptyFixed + customSeries + (combined.points.isEmpty ? [] : [combined])
        let emptyLifts = fixedSeries.filter { $0.points.isEmpty }.map(\.exercise)
        return StrengthProgressChartData(series: allSeries,
                                         emptyLifts: emptyLifts)
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
