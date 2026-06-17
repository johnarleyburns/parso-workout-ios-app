import Foundation

/// How the latest result of an assessment series compares to its baseline, after
/// applying a minimal-detectable-change (MDC) guardrail so measurement noise isn't
/// read as real progress (§04).
public enum AssessmentTrend: String, Sendable, Equatable {
    case improved
    case declined
    case unchanged   // within the noise band
    case single      // only one data point — no trend yet
}

/// A longitudinal snapshot of one assessment series (one kind, one lift for
/// lift-specific kinds). Pure value type built by `AssessmentMath`.
public struct AssessmentSummary: Sendable, Equatable, Identifiable {
    public let kind: AssessmentKind
    public let exerciseName: String?   // set only for lift-specific kinds
    public let latest: Double
    public let latestDate: Date
    public let baseline: Double         // the first recorded result in the series
    public let baselineDate: Date
    public let best: Double             // best result ever (higher-is-better)
    public let count: Int

    public init(kind: AssessmentKind, exerciseName: String?,
                latest: Double, latestDate: Date,
                baseline: Double, baselineDate: Date,
                best: Double, count: Int) {
        self.kind = kind
        self.exerciseName = exerciseName
        self.latest = latest
        self.latestDate = latestDate
        self.baseline = baseline
        self.baselineDate = baselineDate
        self.best = best
        self.count = count
    }

    /// Stable id matching `Assessment.seriesKey`.
    public var id: String {
        kind.concernsLift ? "\(kind.rawValue)::\(exerciseName ?? "")" : kind.rawValue
    }

    /// Absolute change from baseline to latest (positive = improvement, since the
    /// whole battery is higher-is-better).
    public var delta: Double { latest - baseline }

    /// Fractional change from baseline (0 when baseline is non-positive).
    public var percentChange: Double { baseline > 0 ? (latest - baseline) / baseline : 0 }

    /// Whole days since the most recent test in this series.
    public func daysSinceLatest(now: Date = Date(), calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: latestDate),
                                       to: calendar.startOfDay(for: now)).day ?? 0)
    }

    /// Trend after the MDC guardrail. A single data point is `.single`.
    public var trend: AssessmentTrend {
        guard count >= 2 else { return .single }
        let mdc = AssessmentMath.minimalDetectableChange(for: kind, baseline: baseline)
        if delta >= mdc { return .improved }
        if delta <= -mdc { return .declined }
        return .unchanged
    }
}

/// Pure assessment computations — estimation, longitudinal summaries, and the
/// re-test cadence. No I/O, fully `swift test`-able.
public enum AssessmentMath {

    /// Estimated 1RM for an `e1RM` test from its raw load × reps. Reuses the same
    /// formula the rest of the app uses for set-level e1RM.
    public static func e1RM(weight: Double, reps: Int, formula: OneRepMaxFormula = .epley) -> Double {
        WorkoutMath.estimated1RM(weight: weight, reps: reps, formula: formula)
    }

    /// The smallest change in a series we treat as real rather than noise. A
    /// fraction of baseline with an absolute floor, tuned per unit so a 1-rep or
    /// few-second wobble on small values doesn't register as progress.
    public static func minimalDetectableChange(for kind: AssessmentKind, baseline: Double) -> Double {
        switch kind.unit {
        case .weightKg:
            // ~3% of estimated 1RM, day-to-day strength-testing reliability.
            return max(1.0, abs(baseline) * 0.03)
        case .reps:
            // One rep, or 10% of baseline for higher-rep tests.
            return max(1.0, abs(baseline) * 0.10)
        case .seconds:
            // Three seconds, or 10% of baseline for longer holds.
            return max(3.0, abs(baseline) * 0.10)
        case .mlKgMin:
            // ~5% of VO₂max, roughly the test-retest reliability of submaximal
            // and field-based VO₂max estimates (floor 1 mL/kg/min).
            return max(1.0, abs(baseline) * 0.05)
        case .watts:
            // ~5% of peak power (Wingate test-retest reliability), floor 10 W.
            return max(10.0, abs(baseline) * 0.05)
        }
    }

    /// Default re-test cadence: the engine suggests re-testing at the end of a
    /// typical training block (decision D5: ~6–8 weeks, app-suggested, opt-in).
    public static let defaultRetestDays = 42

    /// A series is due for a re-test once it's been at least `cadenceDays` since
    /// its most recent result.
    public static func isRetestDue(_ summary: AssessmentSummary,
                                   cadenceDays: Int = defaultRetestDays,
                                   now: Date = Date()) -> Bool {
        summary.daysSinceLatest(now: now) >= cadenceDays
    }

    /// Collapse a flat list of `Assessment` rows into one summary per series,
    /// ordered by most-recent activity first. Pure: callers pass their `@Query`
    /// array straight in.
    public static func summaries(from assessments: [Assessment]) -> [AssessmentSummary] {
        var groups: [String: [Assessment]] = [:]
        for a in assessments {
            groups[a.seriesKey, default: []].append(a)
        }
        var out: [AssessmentSummary] = []
        for (_, rows) in groups {
            let sorted = rows.sorted { $0.date < $1.date }
            guard let first = sorted.first, let last = sorted.last else { continue }
            let best = sorted.map(\.value).max() ?? last.value
            out.append(AssessmentSummary(
                kind: last.kindValue,
                exerciseName: last.kindValue.concernsLift ? last.exerciseName : nil,
                latest: last.value,
                latestDate: last.date,
                baseline: first.value,
                baselineDate: first.date,
                best: best,
                count: sorted.count))
        }
        return out.sorted { $0.latestDate > $1.latestDate }
    }
}
