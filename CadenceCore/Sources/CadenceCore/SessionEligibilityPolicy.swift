import Foundation

public enum EligibilityDecision: Sendable, Equatable {
    case eligible(notes: [DecisionNote])
    case deferred(until: Date, reasons: [DecisionReason])
    case blocked(reasons: [DecisionReason])
}

public struct DecisionReason: Sendable, Equatable, Identifiable {
    public let id: String
    public let message: String
    public let citationIds: [String]

    public init(id: String, message: String, citationIds: [String] = []) {
        self.id = id
        self.message = message
        self.citationIds = citationIds
    }
}

public struct DecisionNote: Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public enum SessionEligibilityPolicy {

    public static func evaluate(_ session: CoachSession, facts: CoachFacts) -> EligibilityDecision {
        var notes: [DecisionNote] = []
        var reasons: [DecisionReason] = []

        if session.kind == .rest { return .eligible(notes: [DecisionNote("Rest is always eligible.")]) }

        let now = facts.referenceDate
        let recovery = facts.recovery

        if let active = facts.events.first(where: { $0.completion == .inProgress }) {
            return .deferred(until: active.start, reasons: [
                DecisionReason(id: "activeWorkout", message: "A workout is currently in progress. Finish or discard it first.", citationIds: [])
            ])
        }

        // Readiness gate: a poor self-reported check-in defers hard work for a day.
        // Easy aerobic, recovery, and rest stay eligible so there's always a path.
        if session.isHard, let readiness = facts.readiness, readiness.isPoor {
            return .deferred(until: now.addingTimeInterval(86400), reasons: [
                DecisionReason(
                    id: "lowReadiness",
                    message: "Your latest check-in flagged poor recovery (soreness, sleep, stress, or energy). Easy movement or recovery is a better fit today.",
                    citationIds: CitationRegistry.citationPool(for: .recoveryMonitoring).citationIds)
            ])
        }

        if session.kind == .strength {
            evaluateStrength(session, recovery: recovery, facts: facts, now: now, notes: &notes, reasons: &reasons)
        }

        if session.kind == .easyAerobic || session.kind == .moderateAerobic || session.kind == .vo2Intervals {
            evaluateAerobic(session, recovery: recovery, facts: facts, now: now, notes: &notes, reasons: &reasons)
        }

        if !reasons.isEmpty {
            let latest = deferredUntil(for: session, facts: facts, now: now) ?? now
            return .deferred(until: latest, reasons: reasons)
        }

        return .eligible(notes: notes)
    }

    private static func evaluateStrength(_ session: CoachSession, recovery: RecoveryState,
                                          facts: CoachFacts, now: Date,
                                          notes: inout [DecisionNote], reasons: inout [DecisionReason]) {
        guard let exercises = session.exercises, !exercises.isEmpty else { return }

        for ex in exercises {
            let exerciseName = ex.name
            let patterns = MovementPattern.patterns(forExerciseNamed: exerciseName, primaryMuscles: ex.primaryMuscles)
            let bodyParts = BodyPart.parts(forMuscleIDs: ex.primaryMuscles)

            if let window = recovery.byExercise[exerciseName], now < window.hardEligibleAt {
                let hrs = Int(window.hardEligibleAt.timeIntervalSince(now) / 3600) + 1
                reasons.append(DecisionReason(
                    id: "exactLift.\(exerciseName)",
                    message: "\(exerciseName) is recovering — eligible again in about \(hrs)h (last hard set \(formatRelative(window.lastExposedAt, now))).",
                    citationIds: ["parejaBlancoRecovery2020"]
                ))
            }

            for pattern in patterns {
                if let window = recovery.byPattern[pattern], now < window.hardEligibleAt {
                    let hrs = Int(window.hardEligibleAt.timeIntervalSince(now) / 3600) + 1
                    reasons.append(DecisionReason(
                        id: "pattern.\(pattern.rawValue)",
                        message: "\(pattern.displayName) pattern is recovering — eligible in about \(hrs)h.",
                        citationIds: ["parejaBlancoRecovery2020"]
                    ))
                }
            }

            for part in bodyParts {
                if let window = recovery.byBodyPart[part], now < window.hardEligibleAt {
                    let hrs = Int(window.hardEligibleAt.timeIntervalSince(now) / 3600) + 1
                    reasons.append(DecisionReason(
                        id: "bodyPart.\(part.rawValue)",
                        message: "\(part.displayName) muscles are recovering — eligible in about \(hrs)h.",
                        citationIds: ["parejaBlancoRecovery2020"]
                    ))
                }
            }
        }

        if let wb = recovery.wholeBody, wb.reason == .unknownImport, now < wb.hardEligibleAt {
            reasons.append(DecisionReason(
                id: "unknownImport",
                message: "An imported workout may have included strength work — deferring hard training for 24h. Add details or wait.",
                citationIds: []
            ))
        }
    }

    private static func deferredUntil(for session: CoachSession,
                                      facts: CoachFacts,
                                      now: Date) -> Date? {
        var dates: [Date] = []

        if session.kind == .strength, let exercises = session.exercises {
            for ex in exercises {
                let patterns = MovementPattern.patterns(forExerciseNamed: ex.name,
                                                        primaryMuscles: ex.primaryMuscles)
                let bodyParts = BodyPart.parts(forMuscleIDs: ex.primaryMuscles)
                if let w = facts.recovery.byExercise[ex.name], now < w.hardEligibleAt {
                    dates.append(w.hardEligibleAt)
                }
                for pattern in patterns {
                    if let w = facts.recovery.byPattern[pattern], now < w.hardEligibleAt {
                        dates.append(w.hardEligibleAt)
                    }
                }
                for part in bodyParts {
                    if let w = facts.recovery.byBodyPart[part], now < w.hardEligibleAt {
                        dates.append(w.hardEligibleAt)
                    }
                }
            }
            if let wb = facts.recovery.wholeBody, wb.reason == .unknownImport, now < wb.hardEligibleAt {
                dates.append(wb.hardEligibleAt)
            }
        }

        if session.kind == .moderateAerobic || session.kind == .vo2Intervals {
            for event in facts.rolling72hCompletedEvents {
                guard case .strength(let details) = event.kind, let d = details else { continue }
                let hasLowerBody = d.exercises.contains {
                    $0.patterns.contains(where: \.isLowerBody) && $0.hardSetCount > 0
                }
                if hasLowerBody {
                    let until = event.end.addingTimeInterval(24 * 3600)
                    if now < until { dates.append(until) }
                }
            }
        }

        if session.kind == .vo2Intervals,
           let wb = facts.recovery.wholeBody, wb.reason == .unknownImport, now < wb.hardEligibleAt {
            dates.append(wb.hardEligibleAt)
        }

        return dates.max()
    }

    private static func evaluateAerobic(_ session: CoachSession, recovery: RecoveryState,
                                         facts: CoachFacts, now: Date,
                                         notes: inout [DecisionNote], reasons: inout [DecisionReason]) {
        let isHard = session.kind == .vo2Intervals

        for event in facts.rolling72hCompletedEvents {
            guard case .strength(let details) = event.kind, let d = details else { continue }
            let hasLowerBody = d.exercises.contains { $0.patterns.contains(where: \.isLowerBody) && $0.hardSetCount > 0 }
            guard hasLowerBody else { continue }

            let hoursSince = now.timeIntervalSince(event.end) / 3600
            if hoursSince < 24 && (isHard || session.kind == .moderateAerobic) {
                reasons.append(DecisionReason(
                    id: "lowerBodyCollision",
                    message: "Hard lower-body strength \(formatRelative(event.end, now)) — deferring hard cardio. Easy walking or cycling is still fine.",
                    citationIds: ["schumannConcurrent2022"]
                ))
            }
        }

        if let wb = recovery.wholeBody, wb.reason == .unknownImport, now < wb.hardEligibleAt, isHard {
            reasons.append(DecisionReason(
                id: "unknownImportCardio",
                message: "An imported workout may include strength work — deferring hard cardio for 24h.",
                citationIds: []
            ))
        }
    }

    public static func evaluatePainConcern(hasPainConcern: Bool, facts: CoachFacts) -> EligibilityDecision? {
        guard hasPainConcern else { return nil }
        return .blocked(reasons: [
            DecisionReason(
                id: "painConcern",
                message: "You reported pain or illness concern. Choose rest or easy activity. If symptoms persist, seek qualified medical advice.",
                citationIds: ["meeusenOvertraining2013"]
            )
        ])
    }

    private static func formatRelative(_ date: Date, _ now: Date) -> String {
        let mins = Int(now.timeIntervalSince(date) / 60)
        if mins < 120 { return "\(mins)m ago" }
        let hrs = mins / 60
        if hrs < 48 { return "\(hrs)h ago" }
        return "\(hrs / 24)d ago"
    }
}
