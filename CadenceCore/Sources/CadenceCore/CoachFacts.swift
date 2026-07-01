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
    case bodyPart
    case fatigue
    case pain
    case none
}

public struct RecoveryState: Sendable, Equatable {
    public let byExercise: [String: RecoveryWindow]
    public let byPattern: [MovementPattern: RecoveryWindow]
    public let byBodyPart: [BodyPart: RecoveryWindow]
    public let wholeBody: RecoveryWindow?

    public static let empty = RecoveryState(byExercise: [:], byPattern: [:], byBodyPart: [:], wholeBody: nil)

    public init(byExercise: [String: RecoveryWindow], byPattern: [MovementPattern: RecoveryWindow],
                byBodyPart: [BodyPart: RecoveryWindow], wholeBody: RecoveryWindow?) {
        self.byExercise = byExercise
        self.byPattern = byPattern
        self.byBodyPart = byBodyPart
        self.wholeBody = wholeBody
    }

    public func isHardEligible(exercise: String, patterns: Set<MovementPattern>,
                                bodyParts: Set<BodyPart>, now: Date) -> Bool {
        if let w = byExercise[exercise], now < w.hardEligibleAt { return false }
        for p in patterns {
            if let w = byPattern[p], now < w.hardEligibleAt { return false }
        }
        for p in bodyParts {
            if let w = byBodyPart[p], now < w.hardEligibleAt { return false }
        }
        return true
    }

    public func nextHardEligible(exercise: String, patterns: Set<MovementPattern>,
                                  bodyParts: Set<BodyPart>, now: Date) -> Date {
        var candidates: [Date] = []
        if let w = byExercise[exercise] { candidates.append(w.hardEligibleAt) }
        for p in patterns { if let w = byPattern[p] { candidates.append(w.hardEligibleAt) } }
        for p in bodyParts { if let w = byBodyPart[p] { candidates.append(w.hardEligibleAt) } }
        return candidates.max() ?? now
    }
}

public struct WeeklyBalance: Sendable, Equatable {
    public let strengthDays: Int
    public let cardioDays: Int
    public let patternsTrained: Set<MovementPattern>
    public let bodyPartsTrained: Set<BodyPart>
    public let fractionalSets: [BodyPart: Double]
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

    public static let empty = WeeklyBalance(
        strengthDays: 0, cardioDays: 0, patternsTrained: [], bodyPartsTrained: [],
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
                stepSummary: StepActivitySummary? = nil) {
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
                     formula: OneRepMaxFormula = .epley,
                     now: Date = Date()) -> CoachFacts {

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
        let readiness = readinessEntry.map { ReadinessSnapshot.from($0, now: now) }

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
            aerobicMinutesByBucket: aerobicBuckets
        )
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
            stepSummary: summary
        )
    }

    private static func computeRecovery(completed: [TrainingEvent],
                                         inProgress: [TrainingEvent],
                                         now: Date) -> RecoveryState {
        var byExercise: [String: RecoveryWindow] = [:]
        var byPattern: [MovementPattern: RecoveryWindow] = [:]
        var byBodyPart: [BodyPart: RecoveryWindow] = [:]
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

                for part in ex.bodyParts {
                    let bw = RecoveryWindow(
                        lastExposedAt: ex.lastWorkingSetAt,
                        hardEligibleAt: ex.lastWorkingSetAt.addingTimeInterval(hours * 3600),
                        reason: .bodyPart,
                        confidence: .moderate
                    )
                    if let existing = byBodyPart[part] {
                        byBodyPart[part] = maxWindow(existing, bw)
                    } else {
                        byBodyPart[part] = bw
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

        return RecoveryState(byExercise: byExercise, byPattern: byPattern, byBodyPart: byBodyPart, wholeBody: wholeBody)
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
        var bodyPartsTrained = Set<BodyPart>()
        var fractionalSets: [BodyPart: Double] = [:]

        for event in strengthEvents {
            guard case .strength(let details) = event.kind, let d = details else { continue }
            for ex in d.exercises {
                patternsTrained.formUnion(ex.patterns)
                bodyPartsTrained.formUnion(ex.bodyParts)
                for part in ex.bodyParts {
                    fractionalSets[part, default: 0] += Double(ex.hardSetCount)
                }
            }
        }

        var moderateMinutes: Double = 0
        var vigorousMinutes: Double = 0
        for event in aerobicEvents {
            let d: AerobicEventDetails
            switch event.kind {
            case .aerobic(let ad): d = ad
            case .intervals(let ad): d = ad
            default: continue
            }
            let mins = d.duration / 60
            switch d.intensity {
            case .easy: moderateMinutes += mins * 0.5
            case .moderate: moderateMinutes += mins
            case .vigorous: vigorousMinutes += mins
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
            bodyPartsTrained: bodyPartsTrained,
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
            dataCompleteness: .moderate
        )
    }
}
