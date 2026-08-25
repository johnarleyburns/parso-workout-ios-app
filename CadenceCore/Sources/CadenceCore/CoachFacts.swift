import Foundation

public struct RecoveryWindow: Sendable, Equatable {
    public let lastExposedAt: Date
    public let hardEligibleAt: Date
    public let reason: RecoveryReason
    public let confidence: FactConfidence

    public init(lastExposedAt: Date, hardEligibleAt: Date, reason: RecoveryReason, confidence: FactConfidence) {
        self.lastExposedAt = lastExposedAt
        self.hardEligibleAt = hardEligibleAt
        self.reason = reason
        self.confidence = confidence
    }
}

public enum RecoveryReason: String, Sendable, Equatable {
    case exactLift
    case pattern
    case muscleGroup
    case fatigue
    case pain
    case none
}

public struct RecoveryState: Sendable, Equatable {
    public let byExercise: [String: RecoveryWindow]
    public let byPattern: [MovementPattern: RecoveryWindow]
    public let byGroup: [MuscleGroup: RecoveryWindow]
    public let wholeBody: RecoveryWindow?
    /// Soft recency penalty (0.0 = fully recovered, 1.0 = just trained). Keyed
    /// by canonical exercise name, movement family, and muscle group. Penalty decays
    /// linearly from 1.0 at 0h to 0.0 at 48h.
    public let softByExercise: [String: Double]
    public let softByFamily: [MovementFamily: Double]
    public let softByGroup: [MuscleGroup: Double]

    public static let empty = RecoveryState(byExercise: [:], byPattern: [:], byGroup: [:],
                                             wholeBody: nil,
                                             softByExercise: [:], softByFamily: [:], softByGroup: [:])

    public init(byExercise: [String: RecoveryWindow], byPattern: [MovementPattern: RecoveryWindow],
                byGroup: [MuscleGroup: RecoveryWindow], wholeBody: RecoveryWindow?,
                softByExercise: [String: Double] = [:], softByFamily: [MovementFamily: Double] = [:],
                softByGroup: [MuscleGroup: Double] = [:]) {
        self.byExercise = byExercise
        self.byPattern = byPattern
        self.byGroup = byGroup
        self.wholeBody = wholeBody
        self.softByExercise = softByExercise
        self.softByFamily = softByFamily
        self.softByGroup = softByGroup
    }

    public func isHardEligible(exercise: String, patterns: Set<MovementPattern>,
                                muscleGroups: Set<MuscleGroup>, now: Date) -> Bool {
        if let w = byExercise[exercise], now < w.hardEligibleAt { return false }
        for p in patterns {
            if let w = byPattern[p], now < w.hardEligibleAt { return false }
        }
        for g in muscleGroups {
            if let w = byGroup[g], now < w.hardEligibleAt { return false }
        }
        return true
    }

    public func nextHardEligible(exercise: String, patterns: Set<MovementPattern>,
                                  muscleGroups: Set<MuscleGroup>, now: Date) -> Date {
        var candidates: [Date] = []
        if let w = byExercise[exercise] { candidates.append(w.hardEligibleAt) }
        for p in patterns { if let w = byPattern[p] { candidates.append(w.hardEligibleAt) } }
        for g in muscleGroups { if let w = byGroup[g] { candidates.append(w.hardEligibleAt) } }
        return candidates.max() ?? now
    }

    public func softPenalty(forExerciseNamed name: String,
                             primaryMuscles: [String] = [],
                             muscleGroups: Set<MuscleGroup> = []) -> Double {
        let canonical = ExerciseNameCanonicalizer.canonicalName(name)
        let namePenalty = softByExercise[canonical] ?? 0
        let family = MovementFamily.family(forExerciseNamed: name, primaryMuscles: primaryMuscles)
        let familyPenalty = softByFamily[family] ?? 0
        let maxGroupPenalty = muscleGroups.map { softByGroup[$0] ?? 0 }.max() ?? 0
        return max(namePenalty, familyPenalty, maxGroupPenalty)
    }

    /// The per-exercise (canonical-name) recency penalty only, excluding the
    /// coarser family/muscle-group components. Two lifts in the same movement family
    /// share the family penalty, so this finer signal is what distinguishes them
    /// when rotating within a pattern (see `CoachSession.mostTrainedExercises`).
    public func softNamePenalty(forExerciseNamed name: String) -> Double {
        softByExercise[ExerciseNameCanonicalizer.canonicalName(name)] ?? 0
    }
}

public struct WeeklyBalance: Sendable, Equatable {
    public let strengthDays: Int
    public let cardioDays: Int
    public let patternsTrained: Set<MovementPattern>
    public let muscleGroupsTrained: Set<MuscleGroup>
    public let fractionalSets: [MuscleGroup: Double]
    public let moderateMinutes: Double
    public let vigorousMinutes: Double
    public let moderateEquivalentMinutes: Double
    public let hardDays: Int
    public let consecutiveHardDays: Int
    public let vo2maxLatest: Double?
    public let vo2maxProtocol: String?
    public let vo2maxTrend: TrendDirection?
    public let readinessAvailable: Bool
    public let dataCompleteness: FactConfidence
    /// Raw wall-clock aerobic minutes by intensity, BEFORE the public-health
    /// weighting is applied. `moderateMinutes` folds easy work in at half credit
    /// and `moderateEquivalentMinutes` counts vigorous work double, which is why
    /// 80 logged minutes can read as 158 "of 150" — surfacing the unweighted
    /// split is what makes that legible (field test 2026-08-19 #7).
    public var easyMinutesLogged: Double = 0
    public var moderateMinutesLogged: Double = 0
    public var vigorousMinutesLogged: Double = 0

    /// Total minutes actually spent doing aerobic work this week.
    public var loggedAerobicMinutes: Double {
        easyMinutesLogged + moderateMinutesLogged + vigorousMinutesLogged
    }

    public static let empty = WeeklyBalance(
        strengthDays: 0, cardioDays: 0, patternsTrained: [], muscleGroupsTrained: [],
        fractionalSets: [:], moderateMinutes: 0, vigorousMinutes: 0,
        moderateEquivalentMinutes: 0, hardDays: 0, consecutiveHardDays: 0,
        vo2maxLatest: nil, vo2maxProtocol: nil, vo2maxTrend: nil,
        readinessAvailable: false, dataCompleteness: .low
    )
}

public struct CoachFacts: Sendable {
    public let events: [TrainingEvent]
    public let recovery: RecoveryState
    public let weeklyBalance: WeeklyBalance
    public let goal: TrainingGoal
    public let experience: ExperienceLevel
    public let referenceDate: Date

    public let rolling72hCompletedEvents: [TrainingEvent]
    public let rolling7dCompletedEvents: [TrainingEvent]
    public let rolling28dCompletedEvents: [TrainingEvent]

    // MARK: Multi-system facts (Phase 2). Additive — not yet consumed by the
    // decision engine, so primary behavior is unchanged.
    public let systemLoads: [TrainingSystem: SystemLoad]
    public let readiness: ReadinessSnapshot?
    public let assessmentCoverage: [TrainingSystem: AssessmentCoverage]
    public let loadSpikeFlags: [LoadSpikeFlag]
    public let zoneSource: CardioZoneSource
    public let aerobicMinutesByBucket: [AerobicIntensityBucket: Double]

    public let stepSummary: StepActivitySummary?
    public let recoveryAwareCoachV2: Bool

    public init(events: [TrainingEvent],
                recovery: RecoveryState,
                weeklyBalance: WeeklyBalance,
                goal: TrainingGoal,
                experience: ExperienceLevel,
                referenceDate: Date,
                rolling72hCompletedEvents: [TrainingEvent],
                rolling7dCompletedEvents: [TrainingEvent],
                rolling28dCompletedEvents: [TrainingEvent],
                systemLoads: [TrainingSystem: SystemLoad] = [:],
                readiness: ReadinessSnapshot? = nil,
                assessmentCoverage: [TrainingSystem: AssessmentCoverage] = [:],
                loadSpikeFlags: [LoadSpikeFlag] = [],
                zoneSource: CardioZoneSource = .unknown,
                aerobicMinutesByBucket: [AerobicIntensityBucket: Double] = [:],
                stepSummary: StepActivitySummary? = nil,
                recoveryAwareCoachV2: Bool = true) {
        self.events = events
        self.recovery = recovery
        self.weeklyBalance = weeklyBalance
        self.goal = goal
        self.experience = experience
        self.referenceDate = referenceDate
        self.rolling72hCompletedEvents = rolling72hCompletedEvents
        self.rolling7dCompletedEvents = rolling7dCompletedEvents
        self.rolling28dCompletedEvents = rolling28dCompletedEvents
        self.systemLoads = systemLoads
        self.readiness = readiness
        self.assessmentCoverage = assessmentCoverage
        self.loadSpikeFlags = loadSpikeFlags
        self.zoneSource = zoneSource
        self.aerobicMinutesByBucket = aerobicMinutesByBucket
        self.stepSummary = stepSummary
        self.recoveryAwareCoachV2 = recoveryAwareCoachV2
    }

    /// Systems with no exposure this week (or never), most-stale first. The basis for
    /// "which systems are stale" explanations.
    public var staleSystems: [TrainingSystem] {
        systemLoads.values
            .filter { $0.isStale }
            .sorted { ($0.daysSinceLastExposure ?? .max) > ($1.daysSinceLastExposure ?? .max) }
            .map(\.system)
    }

    public var todayCompletedEvents: [TrainingEvent] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: referenceDate)
        return rolling7dCompletedEvents.filter {
            $0.start >= todayStart && $0.end <= referenceDate
        }
    }

    public var tomorrow: Date {
        referenceDate.addingTimeInterval(86400)
    }
}

public extension CoachFacts {

    static func make(from events: [TrainingEvent],
                     goal: TrainingGoal,
                     experience: ExperienceLevel,
                     assessments: [AssessmentSummary] = [],
                     readinessEntry: ReadinessEntry? = nil,
                     readinessSnapshot: ReadinessSnapshot? = nil,
                     formula: OneRepMaxFormula = .epley,
                     now: Date = Date(),
                     passiveSamples: [PassiveReadinessSample] = []) -> CoachFacts {
        return make(from: events, goal: goal, experience: experience,
                    assessments: assessments, readinessEntry: readinessEntry,
                    readinessSnapshot: readinessSnapshot,
                    formula: formula, now: now, passiveSamples: passiveSamples,
                    recoveryAwareCoachV2: true)
    }

    static func make(from events: [TrainingEvent],
                     goal: TrainingGoal,
                     experience: ExperienceLevel,
                     assessments: [AssessmentSummary] = [],
                     readinessEntry: ReadinessEntry? = nil,
                     readinessSnapshot: ReadinessSnapshot? = nil,
                     formula: OneRepMaxFormula = .epley,
                     now: Date = Date(),
                     passiveSamples: [PassiveReadinessSample] = [],
                     recoveryAwareCoachV2: Bool) -> CoachFacts {

        // Completed events only, in the past, sorted chronologically (newest last).
        // Sorting here makes every downstream "last X" lookup and rolling window
        // deterministic regardless of the order Home supplies events in.
        let completed = events
            .filter { $0.completion == .completed && $0.end <= now }
            .sorted { $0.end < $1.end }
        let inProgress = events.filter { $0.completion == .inProgress }

        // Rolling windows carry explicit lower and upper bounds; the upper bound
        // (`<= now`) keeps future-dated events out of every window.
        let rolling72h = completed.filter { $0.end >= now.addingTimeInterval(-72 * 3600) && $0.end <= now }
        let rolling7d = completed.filter { $0.end >= now.addingTimeInterval(-7 * 86400) && $0.end <= now }
        let rolling28d = completed.filter { $0.end >= now.addingTimeInterval(-28 * 86400) && $0.end <= now }
        let thisWeekStart = WeeklyStats.weekStart(now: now)
        let thisWeek = completed.filter { $0.start >= thisWeekStart && $0.start <= now }

        let recovery = computeRecovery(completed: rolling72h, inProgress: inProgress, now: now)
        let balance = computeWeeklyBalance(completed: thisWeek, now: now)

        // Phase 2 multi-system facts (additive — decision engine unchanged).
        let systemLoads = SystemLoadComputer.loads(rolling7d: rolling7d, rolling28d: rolling28d, now: now)
        let aerobicBuckets = SystemLoadComputer.aerobicMinutesByBucket(rolling7d: rolling7d)
        let spikeFlags = SystemLoadComputer.loadSpikeFlags(systemLoads)
        let zoneSrc = SystemLoadComputer.zoneSource(rolling28d: rolling28d)
        let coverage = SystemLoadComputer.assessmentCoverage(assessments, now: now)
        let selfReport = readinessSnapshot ?? readinessEntry.map { ReadinessSnapshot.from($0, now: now) }

        // Passive readiness fusion (revenue Phase 4, D4). Self-report stays
        // authoritative where present; passive HealthKit signals fill the gap and
        // can prompt a check-in. When there is neither a check-in nor enough passive
        // data, `readiness` stays exactly what it was before (nil / self-report).
        let passiveSignal = passiveSamples.isEmpty
            ? PassiveReadinessSignal.insufficient
            : PassiveReadinessAnalyzer.signal(samples: passiveSamples, now: now)
        let readiness: ReadinessSnapshot?
        if selfReport == nil && !passiveSignal.makesClaim {
            readiness = nil
        } else {
            readiness = ReadinessFusion.fuse(selfReport: selfReport, passive: passiveSignal, now: now)
        }

        return CoachFacts(
            events: events,
            recovery: recovery,
            weeklyBalance: balance,
            goal: goal,
            experience: experience,
            referenceDate: now,
            rolling72hCompletedEvents: rolling72h,
            rolling7dCompletedEvents: rolling7d,
            rolling28dCompletedEvents: rolling28d,
            systemLoads: systemLoads,
            readiness: readiness,
            assessmentCoverage: coverage,
            loadSpikeFlags: spikeFlags,
            zoneSource: zoneSrc,
            aerobicMinutesByBucket: aerobicBuckets,
            recoveryAwareCoachV2: recoveryAwareCoachV2
        )
    }

    /// Phase F (field-test-fixes): returns a copy of these facts with step
    /// summary overlaid. This avoids re-running the entire pipeline when only
    /// the step count data needs a refresh.
    func withStepSummary(from activityTrend: [DayActivity]) -> CoachFacts {
        let summary = StepActivitySummary(from: activityTrend)
        return CoachFacts(
            events: events, recovery: recovery, weeklyBalance: weeklyBalance,
            goal: goal, experience: experience, referenceDate: referenceDate,
            rolling72hCompletedEvents: rolling72hCompletedEvents,
            rolling7dCompletedEvents: rolling7dCompletedEvents,
            rolling28dCompletedEvents: rolling28dCompletedEvents,
            systemLoads: systemLoads, readiness: readiness,
            assessmentCoverage: assessmentCoverage,
            loadSpikeFlags: loadSpikeFlags, zoneSource: zoneSource,
            aerobicMinutesByBucket: aerobicMinutesByBucket,
            stepSummary: summary, recoveryAwareCoachV2: recoveryAwareCoachV2)
    }

    static func make(from events: [TrainingEvent],
                     goal: TrainingGoal,
                     experience: ExperienceLevel,
                     assessments: [AssessmentSummary] = [],
                     readinessEntry: ReadinessEntry? = nil,
                     formula: OneRepMaxFormula = .epley,
                     now: Date = Date(),
                     activityTrend: [DayActivity]) -> CoachFacts {
        let base = make(from: events, goal: goal, experience: experience,
                        assessments: assessments, readinessEntry: readinessEntry,
                        formula: formula, now: now)
        let summary = StepActivitySummary(from: activityTrend)
        return CoachFacts(
            events: base.events,
            recovery: base.recovery,
            weeklyBalance: base.weeklyBalance,
            goal: base.goal,
            experience: base.experience,
            referenceDate: base.referenceDate,
            rolling72hCompletedEvents: base.rolling72hCompletedEvents,
            rolling7dCompletedEvents: base.rolling7dCompletedEvents,
            rolling28dCompletedEvents: base.rolling28dCompletedEvents,
            systemLoads: base.systemLoads,
            readiness: base.readiness,
            assessmentCoverage: base.assessmentCoverage,
            loadSpikeFlags: base.loadSpikeFlags,
            zoneSource: base.zoneSource,
            aerobicMinutesByBucket: base.aerobicMinutesByBucket,
            stepSummary: summary,
            recoveryAwareCoachV2: base.recoveryAwareCoachV2
        )
    }

    private static func computeRecovery(completed: [TrainingEvent],
                                         inProgress: [TrainingEvent],
                                         now: Date) -> RecoveryState {
        var byExercise: [String: RecoveryWindow] = [:]
        var byPattern: [MovementPattern: RecoveryWindow] = [:]
        var byGroup: [MuscleGroup: RecoveryWindow] = [:]
        var wholeBodyLatest: Date?

        for event in completed {
            guard case .strength(let details) = event.kind, let d = details else { continue }

            for ex in d.exercises where ex.isHard {
                let isHighFatigue = ex.reachedFailure || (ex.maxRPE ?? 0) >= 9 || d.totalHardSets >= 20
                let hours: TimeInterval = isHighFatigue ? 72 : 48

                let window = RecoveryWindow(
                    lastExposedAt: ex.lastWorkingSetAt,
                    hardEligibleAt: ex.lastWorkingSetAt.addingTimeInterval(hours * 3600),
                    reason: .exactLift,
                    confidence: isHighFatigue ? .high : .moderate
                )

                if let existing = byExercise[ex.exerciseName] {
                    byExercise[ex.exerciseName] = maxWindow(existing, window)
                } else {
                    byExercise[ex.exerciseName] = window
                }

                for pattern in ex.patterns {
                    let pw = RecoveryWindow(
                        lastExposedAt: ex.lastWorkingSetAt,
                        hardEligibleAt: ex.lastWorkingSetAt.addingTimeInterval(hours * 3600),
                        reason: .pattern,
                        confidence: .moderate
                    )
                    if let existing = byPattern[pattern] {
                        byPattern[pattern] = maxWindow(existing, pw)
                    } else {
                        byPattern[pattern] = pw
                    }
                }

                for group in ex.muscleGroups {
                    let bw = RecoveryWindow(
                        lastExposedAt: ex.lastWorkingSetAt,
                        hardEligibleAt: ex.lastWorkingSetAt.addingTimeInterval(hours * 3600),
                        reason: .muscleGroup,
                        confidence: .moderate
                    )
                    if let existing = byGroup[group] {
                        byGroup[group] = maxWindow(existing, bw)
                    } else {
                        byGroup[group] = bw
                    }
                }

                let exerciseEnd = ex.lastWorkingSetAt
                if wholeBodyLatest == nil || exerciseEnd > wholeBodyLatest! {
                    wholeBodyLatest = exerciseEnd
                }
            }
        }

        let wholeBody: RecoveryWindow?
        if let latest = wholeBodyLatest {
            wholeBody = RecoveryWindow(
                lastExposedAt: latest,
                hardEligibleAt: latest.addingTimeInterval(48 * 3600),
                reason: .none,
                confidence: .moderate
            )
        } else {
            wholeBody = nil
        }

        // Soft tier: all working sets (no isHard filter), penalty decays 1→0 over 48h
        var softByExercise: [String: Double] = [:]
        var softByFamily: [MovementFamily: Double] = [:]
        var softByGroup: [MuscleGroup: Double] = [:]

        for event in completed {
            guard case .strength(let details) = event.kind, let d = details else { continue }
            for ex in d.exercises {
                let hoursSince = now.timeIntervalSince(ex.lastWorkingSetAt) / 3600.0
                let penalty = max(0.0, 1.0 - hoursSince / 48.0)
                guard penalty > 0 else { continue }

                let canonical = ExerciseNameCanonicalizer.canonicalName(ex.exerciseName)
                softByExercise[canonical] = max(softByExercise[canonical] ?? 0, penalty)

                let family = MovementFamily.family(forExerciseNamed: ex.exerciseName,
                                                    primaryMuscles: [])
                softByFamily[family] = max(softByFamily[family] ?? 0, penalty)

                for group in ex.muscleGroups {
                    softByGroup[group] = max(softByGroup[group] ?? 0, penalty)
                }
            }
        }

        return RecoveryState(byExercise: byExercise, byPattern: byPattern, byGroup: byGroup,
                              wholeBody: wholeBody,
                              softByExercise: softByExercise, softByFamily: softByFamily,
                              softByGroup: softByGroup)
    }

    private static func maxWindow(_ a: RecoveryWindow, _ b: RecoveryWindow) -> RecoveryWindow {
        a.hardEligibleAt >= b.hardEligibleAt ? a : b
    }

    private static func computeWeeklyBalance(completed: [TrainingEvent], now: Date) -> WeeklyBalance {
        let strengthEvents = completed.filter { $0.isStrength }
        let aerobicEvents = completed.filter { $0.isAerobic }

        let strengthDays = Set(strengthEvents.map { Calendar.current.startOfDay(for: $0.start) }).count
        let cardioDays = Set(aerobicEvents.map { Calendar.current.startOfDay(for: $0.start) }).count

        var patternsTrained = Set<MovementPattern>()
        var muscleGroupsTrained = Set<MuscleGroup>()
        var fractionalSets: [MuscleGroup: Double] = [:]

        for event in strengthEvents {
            guard case .strength(let details) = event.kind, let d = details else { continue }
            for ex in d.exercises {
                patternsTrained.formUnion(ex.patterns)
                muscleGroupsTrained.formUnion(ex.muscleGroups)
                for group in ex.muscleGroups {
                    fractionalSets[group, default: 0] += Double(ex.hardSetCount)
                }
            }
        }

        var moderateMinutes: Double = 0
        var vigorousMinutes: Double = 0
        var easyLogged: Double = 0
        var moderateLogged: Double = 0
        var vigorousLogged: Double = 0
        for event in aerobicEvents {
            let d: AerobicEventDetails
            switch event.kind {
            case .aerobic(let ad): d = ad
            case .intervals(let ad): d = ad
            default: continue
            }
            let mins = d.duration / 60
            switch d.intensity {
            case .easy: moderateMinutes += mins * 0.5; easyLogged += mins
            case .moderate: moderateMinutes += mins; moderateLogged += mins
            case .vigorous: vigorousMinutes += mins; vigorousLogged += mins
            }
        }
        let modEquiv = moderateMinutes + 2 * vigorousMinutes

        var hardDays = Set<Date>()
        for event in completed where event.isHard {
            hardDays.insert(Calendar.current.startOfDay(for: event.start))
        }

        var consecutiveHard = 0
        var maxConsecutive = 0
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: now.addingTimeInterval(-7 * 86400))
        let today = cal.startOfDay(for: now)
        while cursor <= today {
            if hardDays.contains(cursor) {
                consecutiveHard += 1
                maxConsecutive = max(maxConsecutive, consecutiveHard)
            } else {
                consecutiveHard = 0
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }

        return WeeklyBalance(
            strengthDays: strengthDays,
            cardioDays: cardioDays,
            patternsTrained: patternsTrained,
            muscleGroupsTrained: muscleGroupsTrained,
            fractionalSets: fractionalSets,
            moderateMinutes: moderateMinutes,
            vigorousMinutes: vigorousMinutes,
            moderateEquivalentMinutes: modEquiv,
            hardDays: hardDays.count,
            consecutiveHardDays: maxConsecutive,
            vo2maxLatest: nil,
            vo2maxProtocol: nil,
            vo2maxTrend: nil,
            readinessAvailable: false,
            dataCompleteness: .moderate,
            easyMinutesLogged: easyLogged,
            moderateMinutesLogged: moderateLogged,
            vigorousMinutesLogged: vigorousLogged
        )
    }
}
