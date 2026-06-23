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
    case unknownImport
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
        strengthDays: 0, patternsTrained: [], bodyPartsTrained: [],
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
}

public extension CoachFacts {

    static func make(from events: [TrainingEvent],
                     goal: TrainingGoal,
                     experience: ExperienceLevel,
                     formula: OneRepMaxFormula = .epley,
                     now: Date = Date()) -> CoachFacts {

        let completed = events.filter { $0.completion == .completed }
        let inProgress = events.filter { $0.completion == .inProgress }

        let rolling72h = completed.filter { now.timeIntervalSince($0.end) <= 72 * 3600 }
        let rolling7d = completed.filter { now.timeIntervalSince($0.end) <= 7 * 86400 }
        let rolling28d = completed.filter { now.timeIntervalSince($0.end) <= 28 * 86400 }

        let recovery = computeRecovery(completed: rolling72h, inProgress: inProgress, now: now)
        let balance = computeWeeklyBalance(completed: rolling7d, now: now)

        return CoachFacts(
            events: events,
            recovery: recovery,
            weeklyBalance: balance,
            goal: goal,
            experience: experience,
            referenceDate: now,
            rolling72hCompletedEvents: rolling72h,
            rolling7dCompletedEvents: rolling7d,
            rolling28dCompletedEvents: rolling28d
        )
    }

    private static func computeRecovery(completed: [TrainingEvent],
                                         inProgress: [TrainingEvent],
                                         now: Date) -> RecoveryState {
        var byExercise: [String: RecoveryWindow] = [:]
        var byPattern: [MovementPattern: RecoveryWindow] = [:]
        var byBodyPart: [BodyPart: RecoveryWindow] = [:]
        var wholeBodyLatest: Date?
        var wholeBodyIsUnknown = false

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

        for event in completed {
            guard case .unknown = event.kind else { continue }
            let hoursAgo = now.timeIntervalSince(event.end)
            if hoursAgo < 24 * 3600 {
                wholeBodyIsUnknown = true
                if wholeBodyLatest == nil || event.end > wholeBodyLatest! {
                    wholeBodyLatest = event.end
                }
            }
        }

        let wholeBody: RecoveryWindow?
        if let latest = wholeBodyLatest {
            let hours: TimeInterval = wholeBodyIsUnknown ? 24 : 48
            wholeBody = RecoveryWindow(
                lastExposedAt: latest,
                hardEligibleAt: latest.addingTimeInterval(hours * 3600),
                reason: wholeBodyIsUnknown ? .unknownImport : .none,
                confidence: wholeBodyIsUnknown ? .low : .moderate
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
