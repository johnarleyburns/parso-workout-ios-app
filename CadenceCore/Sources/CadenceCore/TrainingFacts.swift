import Foundation

/// Direction of an estimated-1RM trend for a lift over the analysis window.
public enum TrendDirection: String, Sendable, Equatable {
    case rising
    case flat
    case declining
}

/// How a user's working sets are distributed across load bands, relative to each
/// lift's best estimated 1RM. Used by the intensity×goal insight (§03 rule 2).
/// Fractions sum to ~1 across `sampleCount` weighted sets; empty when no loaded
/// sets are available.
public struct IntensityDistribution: Equatable, Sendable {
    public let heavy: Double     // fraction of sets at ≥80% e1RM (strength range)
    public let moderate: Double  // 60–80% e1RM
    public let light: Double     // <60% e1RM
    public let sampleCount: Int

    public init(heavy: Double, moderate: Double, light: Double, sampleCount: Int) {
        self.heavy = heavy
        self.moderate = moderate
        self.light = light
        self.sampleCount = sampleCount
    }

    public static let empty = IntensityDistribution(heavy: 0, moderate: 0, light: 0, sampleCount: 0)
}

/// A pure, computed snapshot of the user's recent training — the engine's
/// "working memory" (§03). Built from the same `@Model` rows the views already
/// `@Query`, so it stays `swift test`-able with an in-memory store (mirrors
/// `WeeklyStats`). Read-only for P3: it carries facts, not prescriptions.
public struct TrainingFacts: Sendable {
    /// Working sets per body part over the trailing 7 days (primary muscles count
    /// 1.0, secondary 0.5 — see `secondaryWeight`).
    public let weeklySetsByPart: [BodyPart: Double]
    /// Distinct training days per body part over the trailing 7 days.
    public let frequencyByPart: [BodyPart: Int]
    /// Per exercise name: e1RM trend (recent 7 days vs the prior 7), only for lifts
    /// with data in both windows.
    public let e1RMTrendByExercise: [String: TrendDirection]
    /// Load-band distribution of the trailing week's loaded working sets.
    public let intensity: IntensityDistribution
    /// Mean logged RPE over the trailing week's working sets (nil if none logged).
    public let avgRPE: Double?
    /// Mean reps-in-reserve, derived from RPE (`10 - RPE`).
    public var avgRIR: Double? { avgRPE.map { max(0, 10 - $0) } }
    /// Whole days since the most recent session (nil if no history).
    public let daysSinceLastSession: Int?
    /// Total working sets in the trailing week — 0 means cold-start (no history).
    public let totalWorkingSets: Int
    /// Longitudinal assessment series (P4): one summary per test the user has run,
    /// most-recent first. Empty until the user logs an assessment.
    public let assessments: [AssessmentSummary]
    /// Series whose most recent result is older than the re-test cadence (D5),
    /// computed against the snapshot's reference time so rules stay deterministic.
    public let assessmentsDueForRetest: [AssessmentSummary]
    public let goal: TrainingGoal
    public let experience: ExperienceLevel

    /// Secondary muscles receive half credit toward weekly volume (a common,
    /// conservative convention for counting indirect work).
    static let secondaryWeight = 0.5

    public init(weeklySetsByPart: [BodyPart: Double],
                frequencyByPart: [BodyPart: Int],
                e1RMTrendByExercise: [String: TrendDirection],
                intensity: IntensityDistribution,
                avgRPE: Double?,
                daysSinceLastSession: Int?,
                totalWorkingSets: Int,
                assessments: [AssessmentSummary] = [],
                assessmentsDueForRetest: [AssessmentSummary] = [],
                goal: TrainingGoal,
                experience: ExperienceLevel) {
        self.weeklySetsByPart = weeklySetsByPart
        self.frequencyByPart = frequencyByPart
        self.e1RMTrendByExercise = e1RMTrendByExercise
        self.intensity = intensity
        self.avgRPE = avgRPE
        self.daysSinceLastSession = daysSinceLastSession
        self.totalWorkingSets = totalWorkingSets
        self.assessments = assessments
        self.assessmentsDueForRetest = assessmentsDueForRetest
        self.goal = goal
        self.experience = experience
    }
}

public extension TrainingFacts {

    /// Build the snapshot from a user's strength sessions. Pure; the caller passes
    /// its `@Query` array straight in. `now` and `formula` are injectable for tests.
    static func make(sessions: [WorkoutSession],
                     assessments: [Assessment] = [],
                     now: Date = Date(),
                     goal: TrainingGoal,
                     experience: ExperienceLevel,
                     formula: OneRepMaxFormula = .epley) -> TrainingFacts {
        let weekStart = now.addingTimeInterval(-7 * 86_400)
        let priorStart = now.addingTimeInterval(-14 * 86_400)
        let cal = Calendar.current

        // One flat list of (session, owner working set) for the trailing week.
        struct WorkingSet { let date: Date; let set: SetEntry; let exercise: Exercise }
        var weekSets: [WorkingSet] = []
        for session in sessions where session.date >= weekStart && session.date <= now {
            for set in session.orderedSets where !set.isWarmup && set.isOwnerSet && set.reps > 0 {
                guard let ex = set.exercise else { continue }
                weekSets.append(WorkingSet(date: session.date, set: set, exercise: ex))
            }
        }

        // Weekly sets + frequency per part.
        var setsByPart: [BodyPart: Double] = [:]
        var daysByPart: [BodyPart: Set<Date>] = [:]
        for ws in weekSets {
            let primary = BodyPart.parts(forMuscleIDs: ws.exercise.primaryMuscles)
            let secondary = BodyPart.parts(forMuscleIDs: ws.exercise.secondaryMuscles).subtracting(primary)
            let day = cal.startOfDay(for: ws.date)
            for p in primary {
                setsByPart[p, default: 0] += 1.0
                daysByPart[p, default: []].insert(day)
            }
            for p in secondary {
                setsByPart[p, default: 0] += secondaryWeight
                daysByPart[p, default: []].insert(day)
            }
        }
        let frequencyByPart = daysByPart.mapValues { $0.count }

        // e1RM reference per exercise (best across all provided history) + windowed
        // bests for the trend.
        var bestAll: [String: Double] = [:]
        var bestRecent: [String: Double] = [:]
        var bestPrior: [String: Double] = [:]
        for session in sessions {
            for set in session.orderedSets where !set.isWarmup && set.isOwnerSet && set.reps > 0 && set.weight > 0 {
                guard let name = set.exercise?.name, !name.isEmpty else { continue }
                let e1rm = WorkoutMath.estimated1RM(weight: set.weight, reps: set.reps, formula: formula)
                bestAll[name] = max(bestAll[name] ?? 0, e1rm)
                if session.date >= weekStart && session.date <= now {
                    bestRecent[name] = max(bestRecent[name] ?? 0, e1rm)
                } else if session.date >= priorStart && session.date < weekStart {
                    bestPrior[name] = max(bestPrior[name] ?? 0, e1rm)
                }
            }
        }
        var trends: [String: TrendDirection] = [:]
        let trendEpsilon = 0.02   // ±2% counts as flat (noise floor)
        for (name, recent) in bestRecent {
            guard let prior = bestPrior[name], prior > 0 else { continue }
            let ratio = recent / prior
            if ratio > 1 + trendEpsilon { trends[name] = .rising }
            else if ratio < 1 - trendEpsilon { trends[name] = .declining }
            else { trends[name] = .flat }
        }

        // Intensity distribution over loaded week sets (relative to each lift's best).
        var heavy = 0.0, moderate = 0.0, light = 0.0, loaded = 0
        for ws in weekSets where ws.set.weight > 0 {
            guard let name = ws.exercise.name.isEmpty ? nil : ws.exercise.name,
                  let ref = bestAll[name], ref > 0 else { continue }
            let pct = ws.set.weight / ref
            loaded += 1
            if pct >= 0.80 { heavy += 1 }
            else if pct >= 0.60 { moderate += 1 }
            else { light += 1 }
        }
        let intensity: IntensityDistribution = loaded == 0
            ? .empty
            : IntensityDistribution(heavy: heavy / Double(loaded),
                                    moderate: moderate / Double(loaded),
                                    light: light / Double(loaded),
                                    sampleCount: loaded)

        // Average RPE over the week's working sets that logged it.
        let rpes = weekSets.compactMap { $0.set.rpe }
        let avgRPE = rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count)

        // Days since last session (any strength session in history).
        let lastDate = sessions.map(\.date).max()
        let daysSince = lastDate.map { max(0, cal.dateComponents([.day], from: cal.startOfDay(for: $0), to: cal.startOfDay(for: now)).day ?? 0) }

        // Assessment series + which are due for a re-test, against the same `now`.
        let summaries = AssessmentMath.summaries(from: assessments)
        let dueForRetest = summaries.filter { AssessmentMath.isRetestDue($0, now: now) }

        return TrainingFacts(weeklySetsByPart: setsByPart,
                             frequencyByPart: frequencyByPart,
                             e1RMTrendByExercise: trends,
                             intensity: intensity,
                             avgRPE: avgRPE,
                             daysSinceLastSession: daysSince,
                             totalWorkingSets: weekSets.count,
                             assessments: summaries,
                             assessmentsDueForRetest: dueForRetest,
                             goal: goal,
                             experience: experience)
    }
}
