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

/// A per-lift snapshot of the trailing week the prescriptive engine programs from
/// (P5): the heaviest loaded working set, its reps, the best estimated 1RM, and the
/// e1RM trend versus the prior week. Only lifts with a loaded working set this week
/// get one. Canonical kilograms.
public struct LiftSnapshot: Equatable, Sendable {
    public let exercise: String
    public let part: BodyPart?            // primary body part, for grouping
    public let topSetWeightKg: Double     // heaviest loaded working set this week
    public let topSetReps: Int            // reps achieved on that set
    public let bestE1RM: Double           // best estimated 1RM this week
    public let trend: TrendDirection?     // vs the prior week (nil if no prior data)

    public init(exercise: String, part: BodyPart?, topSetWeightKg: Double,
                topSetReps: Int, bestE1RM: Double, trend: TrendDirection?) {
        self.exercise = exercise
        self.part = part
        self.topSetWeightKg = topSetWeightKg
        self.topSetReps = topSetReps
        self.bestE1RM = bestE1RM
        self.trend = trend
    }
}

/// A pure, computed snapshot of the user's recent training — the engine's
/// "working memory" (§03). Built from the same `@Model` rows the views already
/// `@Query`, so it stays `swift test`-able with an in-memory store (mirrors
/// `WeeklyStats`). Read-only for P3: it carries facts, not prescriptions.
public struct TrainingFacts: Sendable {
    /// Working sets per body part over the trailing 7 days (primary muscles count
    /// 1.0, secondary 0.5 — see `secondaryWeight`).
    public let weeklySetsByPart: [BodyPart: Double]
    /// Working sets per *muscle* (`MuscleCatalog` id) over the same window and
    /// with the same primary/secondary weighting. Body parts group several
    /// muscles, so this is the resolution the volume literature actually
    /// prescribes at (field test 2026-08-19 #8).
    public let weeklySetsByMuscle: [String: Double]
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
    /// Total working sets in the trailing week (Monday-to-now). 0 means no sets
    /// this week, not necessarily cold-start — use `allTimeWorkingSets` or
    /// `daysSinceLastSession` for the cold-start gate.
    public let totalWorkingSets: Int
    /// Total working sets across ALL provided sessions (all-time), not just this
    /// week. 0 means true cold-start — no logged working sets ever.
    public let allTimeWorkingSets: Int
    /// Longitudinal assessment series (P4): one summary per test the user has run,
    /// most-recent first. Empty until the user logs an assessment.
    public let assessments: [AssessmentSummary]
    /// Series whose most recent result is older than the re-test cadence (D5),
    /// computed against the snapshot's reference time so rules stay deterministic.
    public let assessmentsDueForRetest: [AssessmentSummary]
    /// Per-lift snapshot of the trailing week, keyed by exercise name — the basis
    /// for the prescriptive engine's next-session targets (P5). Empty at cold-start.
    public let liftSnapshots: [String: LiftSnapshot]
    public let goal: TrainingGoal
    public let experience: ExperienceLevel
    public let incompleteCustomExerciseNames: [String]

    // MARK: Phase 2 multi-system strength deltas (additive; engine behavior unchanged).
    /// Per lift: count of consecutive week-over-week e1RM declines ending this week.
    /// 0 = not currently declining. Basis for the repeated-decline deload trigger (C8).
    public let repeatedDeclineByExercise: [String: Int]
    /// Per lift: number of logged sessions since the last load drop (>10% vs prior
    /// session's top set). Equals the full session count if never deloaded.
    public let sessionsSinceDeloadByExercise: [String: Int]
    /// Per body part: weekly working-set volume trend (this week vs prior week).
    public let volumeTrendByPart: [BodyPart: TrendDirection]

    public var assessedE1RMs: [String: Double] {
        var result: [String: Double] = [:]
        for s in assessments where s.kind == .e1RM {
            if let name = s.exerciseName, !name.isEmpty {
                result[name] = max(result[name] ?? 0, s.latest)
            }
        }
        return result
    }

    private static let vo2maxKinds: Set<AssessmentKind> = [.cooper12min, .run1_5mile, .rockportWalk, .queensCollegeStep, .vo2maxField]

    public var estimatedVO2max: Double? {
        assessments.filter { Self.vo2maxKinds.contains($0.kind) }.map(\.latest).max()
    }

    public var hasAnyAssessment: Bool { !assessments.isEmpty }

    /// Secondary muscles receive half credit toward weekly volume (a common,
    /// conservative convention for counting indirect work).
    static let secondaryWeight = 0.5

    public init(weeklySetsByPart: [BodyPart: Double],
                weeklySetsByMuscle: [String: Double] = [:],
                frequencyByPart: [BodyPart: Int],
                e1RMTrendByExercise: [String: TrendDirection],
                intensity: IntensityDistribution,
                avgRPE: Double?,
                daysSinceLastSession: Int?,
                totalWorkingSets: Int,
                allTimeWorkingSets: Int = 0,
                assessments: [AssessmentSummary] = [],
                assessmentsDueForRetest: [AssessmentSummary] = [],
                liftSnapshots: [String: LiftSnapshot] = [:],
                repeatedDeclineByExercise: [String: Int] = [:],
                sessionsSinceDeloadByExercise: [String: Int] = [:],
                 volumeTrendByPart: [BodyPart: TrendDirection] = [:],
                 goal: TrainingGoal,
                 experience: ExperienceLevel,
                 incompleteCustomExerciseNames: [String] = []) {
        self.weeklySetsByPart = weeklySetsByPart
        self.weeklySetsByMuscle = weeklySetsByMuscle
        self.frequencyByPart = frequencyByPart
        self.e1RMTrendByExercise = e1RMTrendByExercise
        self.intensity = intensity
        self.avgRPE = avgRPE
        self.daysSinceLastSession = daysSinceLastSession
        self.totalWorkingSets = totalWorkingSets
        self.allTimeWorkingSets = allTimeWorkingSets
        self.assessments = assessments
        self.assessmentsDueForRetest = assessmentsDueForRetest
        self.liftSnapshots = liftSnapshots
        self.repeatedDeclineByExercise = repeatedDeclineByExercise
        self.sessionsSinceDeloadByExercise = sessionsSinceDeloadByExercise
        self.volumeTrendByPart = volumeTrendByPart
        self.goal = goal
        self.experience = experience
        self.incompleteCustomExerciseNames = incompleteCustomExerciseNames
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
        let weekStart = WeeklyStats.weekStart(now: now)
        let priorStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? now.addingTimeInterval(-14 * 86_400)
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

        // Weekly sets + frequency per part, and the same tally per muscle.
        var setsByPart: [BodyPart: Double] = [:]
        var daysByPart: [BodyPart: Set<Date>] = [:]
        var setsByMuscle: [String: Double] = [:]
        for ws in weekSets {
            var primary = BodyPart.parts(forMuscleIDs: ws.exercise.primaryMuscles)
            if primary.isEmpty, let cat = ws.exercise.categoryValue {
                primary = BodyPart.parts(forCategory: cat)
            }
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
            var primaryMuscles = Set(ws.exercise.primaryMuscles)
            if primaryMuscles.isEmpty, let cat = ws.exercise.categoryValue {
                primaryMuscles = Set(BodyPart.defaultMuscles(forCategory: cat))
            }
            for id in primaryMuscles where MuscleCatalog.muscle(id) != nil {
                setsByMuscle[id, default: 0] += 1.0
            }
            for id in Set(ws.exercise.secondaryMuscles).subtracting(primaryMuscles)
            where MuscleCatalog.muscle(id) != nil {
                setsByMuscle[id, default: 0] += secondaryWeight
            }
        }
        let frequencyByPart = daysByPart.mapValues { $0.count }

        // e1RM reference per exercise (best across all provided history) + windowed
        // bests for the trend. Uses effective load.
        var bestAll: [String: Double] = [:]
        var bestRecent: [String: Double] = [:]
        var bestPrior: [String: Double] = [:]
        for session in sessions {
            for set in session.orderedSets where !set.isWarmup && set.isOwnerSet && set.reps > 0 && set.effectiveLoadKg > 0 {
                guard let name = set.exercise?.name, !name.isEmpty else { continue }
                let e1rm = WorkoutMath.estimated1RM(weight: set.effectiveLoadKg, reps: set.reps, formula: formula)
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
        // Uses effective load.
        var heavy = 0.0, moderate = 0.0, light = 0.0, loaded = 0
        for ws in weekSets where ws.set.effectiveLoadKg > 0 {
            guard let name = ws.exercise.name.isEmpty ? nil : ws.exercise.name,
                  let ref = bestAll[name], ref > 0 else { continue }
            let pct = ws.set.effectiveLoadKg / ref
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

        // Per-lift snapshot of the trailing week: the heaviest loaded working set
        // (the basis for the next-session prescription) + this week's best e1RM +
        // the trend. Primary body part taken from the heaviest set's exercise.
        // Uses effective load.
        var topSet: [String: (weight: Double, reps: Int, exercise: Exercise)] = [:]
        for ws in weekSets where ws.set.effectiveLoadKg > 0 {
            let name = ws.exercise.name
            guard !name.isEmpty else { continue }
            if let cur = topSet[name], cur.weight >= ws.set.effectiveLoadKg { continue }
            topSet[name] = (ws.set.effectiveLoadKg, ws.set.reps, ws.exercise)
        }
        var liftSnapshots: [String: LiftSnapshot] = [:]
        for (name, top) in topSet {
            let part = BodyPart.parts(forMuscleIDs: top.exercise.primaryMuscles).sorted { $0.rawValue < $1.rawValue }.first
            liftSnapshots[name] = LiftSnapshot(
                exercise: name,
                part: part,
                topSetWeightKg: top.weight,
                topSetReps: top.reps,
                bestE1RM: bestRecent[name] ?? WorkoutMath.estimated1RM(weight: top.weight, reps: top.reps, formula: formula),
                trend: trends[name])
        }

        // Average RPE over the week's working sets that logged it.
        let rpes = weekSets.compactMap { $0.set.rpe }
        let avgRPE = rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count)

        // Days since last session (any strength session in history).
        let lastDate = sessions.map(\.date).max()
        let daysSince = lastDate.map { max(0, cal.dateComponents([.day], from: cal.startOfDay(for: $0), to: cal.startOfDay(for: now)).day ?? 0) }

        // Assessment series + which are due for a re-test, against the same `now`.
        let summaries = AssessmentMath.summaries(from: assessments)
        let dueForRetest = summaries.filter { AssessmentMath.isRetestDue($0, now: now) }

        // Phase 2 strength deltas (additive; not consumed by the engine yet).

        // Prior-week volume per part → weekly volume trend.
        var priorSetsByPart: [BodyPart: Double] = [:]
        for session in sessions where session.date >= priorStart && session.date < weekStart {
            for set in session.orderedSets where !set.isWarmup && set.isOwnerSet && set.reps > 0 {
                guard let ex = set.exercise else { continue }
                let primary = BodyPart.parts(forMuscleIDs: ex.primaryMuscles)
                let secondary = BodyPart.parts(forMuscleIDs: ex.secondaryMuscles).subtracting(primary)
                for p in primary { priorSetsByPart[p, default: 0] += 1.0 }
                for p in secondary { priorSetsByPart[p, default: 0] += secondaryWeight }
            }
        }
        var volumeTrendByPart: [BodyPart: TrendDirection] = [:]
        let volEps = 0.15
        for p in Set(setsByPart.keys).union(priorSetsByPart.keys) {
            let cur = setsByPart[p] ?? 0
            let prior = priorSetsByPart[p] ?? 0
            if prior <= 0 { volumeTrendByPart[p] = cur > 0 ? .rising : .flat; continue }
            let ratio = cur / prior
            if ratio > 1 + volEps { volumeTrendByPart[p] = .rising }
            else if ratio < 1 - volEps { volumeTrendByPart[p] = .declining }
            else { volumeTrendByPart[p] = .flat }
        }

        // Weekly-best e1RM per lift → trailing consecutive-decline count.
        // Uses effective load.
        var weeklyBestE1RM: [String: [Date: Double]] = [:]
        var topByExerciseSession: [String: [(date: Date, weight: Double)]] = [:]
        for session in sessions {
            let wk = WeeklyStats.weekStart(now: session.date)
            var topForEx: [String: Double] = [:]
            for set in session.orderedSets where !set.isWarmup && set.isOwnerSet && set.reps > 0 && set.effectiveLoadKg > 0 {
                guard let name = set.exercise?.name, !name.isEmpty else { continue }
                let e1 = WorkoutMath.estimated1RM(weight: set.effectiveLoadKg, reps: set.reps, formula: formula)
                weeklyBestE1RM[name, default: [:]][wk] = max(weeklyBestE1RM[name]?[wk] ?? 0, e1)
                topForEx[name] = max(topForEx[name] ?? 0, set.effectiveLoadKg)
            }
            for (name, w) in topForEx { topByExerciseSession[name, default: []].append((session.date, w)) }
        }
        var repeatedDecline: [String: Int] = [:]
        let declineEps = 0.02
        for (name, byWeek) in weeklyBestE1RM {
            let ordered = byWeek.sorted { $0.key < $1.key }.map(\.value)
            guard ordered.count >= 2 else { continue }
            var count = 0
            var i = ordered.count - 1
            while i >= 1, ordered[i] < ordered[i - 1] * (1 - declineEps) { count += 1; i -= 1 }
            if count > 0 { repeatedDecline[name] = count }
        }

        // Sessions since the last load drop (>10%).
        var sessionsSinceDeload: [String: Int] = [:]
        for (name, rows) in topByExerciseSession {
            let ordered = rows.sorted { $0.date < $1.date }
            guard !ordered.isEmpty else { continue }
            var lastDeloadIndex: Int?
            if ordered.count >= 2 {
                for k in 1..<ordered.count where ordered[k].weight < ordered[k - 1].weight * 0.9 {
                    lastDeloadIndex = k
                }
            }
            sessionsSinceDeload[name] = lastDeloadIndex.map { ordered.count - 1 - $0 } ?? ordered.count
        }

        // All-time working set count (not week-scoped) — the true cold-start gate.
        let allTimeSets = sessions.reduce(0) { count, session in
            count + session.orderedSets.filter { !$0.isWarmup && $0.isOwnerSet && $0.reps > 0 }.count
        }

        // Scan ALL sessions for incomplete custom exercises, not just this week's.
        var incompleteCustom: Set<String> = []
        for session in sessions {
            for set in session.orderedSets where !set.isWarmup && set.isOwnerSet && set.reps > 0 {
                guard let ex = set.exercise, ex.isCustom, ex.primaryMuscles.isEmpty else { continue }
                incompleteCustom.insert(ex.name)
            }
        }
        let incompleteCustomExerciseNames = incompleteCustom.sorted()

        return TrainingFacts(weeklySetsByPart: setsByPart,
                             weeklySetsByMuscle: setsByMuscle,
                             frequencyByPart: frequencyByPart,
                             e1RMTrendByExercise: trends,
                             intensity: intensity,
                             avgRPE: avgRPE,
                             daysSinceLastSession: daysSince,
                             totalWorkingSets: weekSets.count,
                             allTimeWorkingSets: allTimeSets,
                             assessments: summaries,
                             assessmentsDueForRetest: dueForRetest,
                             liftSnapshots: liftSnapshots,
                             repeatedDeclineByExercise: repeatedDecline,
                             sessionsSinceDeloadByExercise: sessionsSinceDeload,
                             volumeTrendByPart: volumeTrendByPart,
                             goal: goal,
                             experience: experience,
                             incompleteCustomExerciseNames: incompleteCustomExerciseNames)
    }
}
