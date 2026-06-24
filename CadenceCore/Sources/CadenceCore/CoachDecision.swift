import Foundation

public struct CoachDecision: Sendable, Identifiable {
    public let id: String
    public let generatedAt: Date
    public let primary: CoachSession
    public let alternatives: [CoachSession]
    public let deferred: [DeferredCandidate]
    public let warnings: [CoachWarning]
    public let observedFacts: [ObservedFact]
    public let weeklyBalance: WeeklyBalance
    public let confidence: FactConfidence
    public let citationIds: [String]
    public let planAdherence: PlanAdherence
    public let todayCompletedMatches: [CoachSession]

    public init(id: String, generatedAt: Date, primary: CoachSession,
                alternatives: [CoachSession] = [], deferred: [DeferredCandidate] = [],
                warnings: [CoachWarning] = [], observedFacts: [ObservedFact] = [],
                weeklyBalance: WeeklyBalance, confidence: FactConfidence,
                citationIds: [String] = [],
                planAdherence: PlanAdherence = .planAhead,
                todayCompletedMatches: [CoachSession] = []) {
        self.id = id
        self.generatedAt = generatedAt
        self.primary = primary
        self.alternatives = alternatives
        self.deferred = deferred
        self.warnings = warnings
        self.observedFacts = observedFacts
        self.weeklyBalance = weeklyBalance
        self.confidence = confidence
        self.citationIds = citationIds
        self.planAdherence = planAdherence
        self.todayCompletedMatches = todayCompletedMatches
    }
}

public struct DeferredCandidate: Sendable, Equatable, Identifiable {
    public let session: CoachSession
    public let reason: DecisionReason
    public var id: String { session.id }
}

public struct CoachWarning: Sendable, Equatable, Identifiable {
    public let id: String
    public let message: String
    public let citationIds: [String]

    public init(id: String, message: String, citationIds: [String] = []) {
        self.id = id
        self.message = message
        self.citationIds = citationIds
    }
}

public struct ObservedFact: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case lastStrength
        case lastCardio
        case weeklyStrengthDays
        case weeklyModerateEquivalentMinutes
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let value: String
    public let detail: String?
    public let occurredAt: Date?

    public init(kind: Kind, title: String, value: String, detail: String? = nil, occurredAt: Date? = nil) {
        self.id = kind.rawValue
        self.kind = kind
        self.title = title
        self.value = value
        self.detail = detail
        self.occurredAt = occurredAt
    }
}

public enum CoachDecisionEngine {

    public static func run(_ facts: CoachFacts,
                           profile: CoachPreferenceProfile = .empty,
                           hasPainConcern: Bool = false) -> CoachDecision {
        let now = facts.referenceDate
        let candidates = CoachSession.candidates(for: facts)
        let todayCompleted = facts.todayCompletedEvents

        // Gate 1: pain/illness block
        if hasPainConcern {
            let restSession = candidates.first { $0.kind == .rest } ?? CoachSession(
                id: "rest.safety", kind: .rest, title: "Rest — safety first",
                subtitle: "Pain or illness reported. Choose rest or easy activity.",
                launchPayload: .rest)
            return CoachDecision(
                id: "decision.\(now.timeIntervalSince1970)",
                generatedAt: now,
                primary: restSession,
                alternatives: [],
                deferred: [],
                warnings: [
                    CoachWarning(id: "painConcern",
                                 message: "You reported pain or illness concern. If symptoms persist, seek qualified medical advice.",
                                 citationIds: ["meeusenOvertraining2013"])
                ],
                observedFacts: [],
                weeklyBalance: facts.weeklyBalance,
                confidence: .high,
                citationIds: ["meeusenOvertraining2013"],
                planAdherence: .planAhead
            )
        }

        // Gate 2: evaluate eligibility for each candidate
        var eligible: [CoachSession] = []
        var deferred: [DeferredCandidate] = []

        for candidate in candidates {
            let decision = SessionEligibilityPolicy.evaluate(candidate, facts: facts)
            switch decision {
            case .eligible:
                eligible.append(candidate)
            case .deferred(_, let reasons):
                for reason in reasons {
                    deferred.append(DeferredCandidate(session: candidate, reason: reason))
                }
            case .blocked(let reasons):
                for reason in reasons {
                    deferred.append(DeferredCandidate(session: candidate, reason: reason))
                }
            }
        }

        // Gate 3: score eligible candidates (base + preference + same-day damping)
        let scored = score(eligible, facts: facts, profile: profile,
                           todayCompleted: todayCompleted)

        let primary: CoachSession
        if let top = scored.first {
            primary = top
        } else {
            primary = candidates.first { $0.kind == .rest } ?? CoachSession(
                id: "rest.fallback", kind: .rest, title: "Rest day",
                subtitle: "No eligible training candidates right now.", launchPayload: .rest)
        }

        let alternatives = Array(scored.dropFirst().prefix(3))

        // Gate 4: Plan adherence — check if today's planned session is already done
        let planState = computePlanAdherence(primary: primary, todayCompleted: todayCompleted,
                                              candidates: candidates, facts: facts)

        // Generate warnings
        let warnings = generateWarnings(facts: facts)

        // Generate observed facts
        var factsList: [ObservedFact] = []

        if let lastStrength = facts.rolling72hCompletedEvents.filter(\.isStrength).max(by: { $0.end < $1.end }) {
            var exerciseDetails: [String] = []
            if case .strength(let d) = lastStrength.kind, let details = d {
                exerciseDetails = details.exercises.map(\.exerciseName)
            }
            factsList.append(ObservedFact(
                kind: .lastStrength,
                title: "Last strength",
                value: formatRelative(lastStrength.end, now),
                detail: exerciseDetails.isEmpty ? nil : exerciseDetails.joined(separator: ", "),
                occurredAt: lastStrength.end
            ))
        }

        if let lastCardio = facts.rolling72hCompletedEvents.filter(\.isAerobic).max(by: { $0.end < $1.end }) {
            var cardioDetail = ""
            if case .aerobic(let d) = lastCardio.kind {
                cardioDetail = "\(d.modality.displayName) · \(Int(d.duration / 60)) min"
            } else if case .intervals(let d) = lastCardio.kind {
                cardioDetail = "\(d.modality.displayName) intervals · \(Int(d.duration / 60)) min"
            }
            factsList.append(ObservedFact(
                kind: .lastCardio,
                title: "Last cardio",
                value: formatRelative(lastCardio.end, now),
                detail: cardioDetail.isEmpty ? nil : cardioDetail,
                occurredAt: lastCardio.end
            ))
        }

        factsList.append(ObservedFact(
            kind: .weeklyStrengthDays,
            title: "Strength days this week",
            value: "\(facts.weeklyBalance.strengthDays) / 2+",
            detail: "Target is 2 or more"
        ))

        factsList.append(ObservedFact(
            kind: .weeklyModerateEquivalentMinutes,
            title: "Moderate-equivalent minutes",
            value: "\(Int(facts.weeklyBalance.moderateEquivalentMinutes)) / 150",
            detail: "Research-informed aerobic target"
        ))

        var allCitationIds = Set(primary.citationIds)
        for w in warnings { allCitationIds.formUnion(w.citationIds) }

        let todayMatches = findTodayPlanMatches(primary: primary, todayCompleted: todayCompleted, candidates: candidates)

        return CoachDecision(
            id: "decision.\(now.timeIntervalSince1970)",
            generatedAt: now,
            primary: primary,
            alternatives: alternatives,
            deferred: deferred,
            warnings: warnings,
            observedFacts: factsList,
            weeklyBalance: facts.weeklyBalance,
            confidence: eligible.isEmpty ? .low : .moderate,
            citationIds: Array(allCitationIds),
            planAdherence: planState,
            todayCompletedMatches: todayMatches
        )
    }

    // MARK: - Plan adherence

    private static func computePlanAdherence(primary: CoachSession,
                                               todayCompleted: [TrainingEvent],
                                               candidates: [CoachSession],
                                               facts: CoachFacts) -> PlanAdherence {
        guard !todayCompleted.isEmpty else { return .planAhead }

        // Check if any completed event today matches the primary recommendation
        var matchedSessions: [(event: TrainingEvent, session: CoachSession)] = []

        for event in todayCompleted {
            for candidate in candidates {
                if eventSatisfiesCoachSession(event, candidate) {
                    matchedSessions.append((event, candidate))
                }
            }
        }

        if !matchedSessions.isEmpty {
            // Plan is complete: find the best match and generate tomorrow preview
            let bestMatch = matchedSessions.first!
            let completedKind = bestMatch.session.kind
            let todayDescription = describeCompletedEvent(bestMatch.event)
            let tomorrowPreview = generateTomorrowPreview(facts: facts, candidates: candidates)

            return .planComplete(completedKind: completedKind,
                                  todayDescription: todayDescription,
                                  tomorrowPreview: tomorrowPreview)
        }

        // Something done today but not matching plan
        return .offPlan(didSomethingToday: true)
    }

    private static func findTodayPlanMatches(primary: CoachSession,
                                               todayCompleted: [TrainingEvent],
                                               candidates: [CoachSession]) -> [CoachSession] {
        var matches: [CoachSession] = []
        for event in todayCompleted {
            for candidate in candidates {
                if eventSatisfiesCoachSession(event, candidate) {
                    matches.append(candidate)
                }
            }
        }
        return matches
    }

    /// Returns true if a completed TrainingEvent satisfies the intent of a CoachSession.
    private static func eventSatisfiesCoachSession(_ event: TrainingEvent, _ session: CoachSession) -> Bool {
        switch (event.kind, session.kind) {
        case (.strength, .strength):
            return true

        case (.aerobic(let d), .moderateAerobic),
             (.aerobic(let d), .easyAerobic),
             (.intervals(let d), .moderateAerobic),
             (.intervals(let d), .easyAerobic):
            // Match by modality if session specifies one
            if let sessionMod = session.modality {
                let eventMod = coachModalityFromAerobic(d.modality)
                guard eventMod == sessionMod else { return false }
            }
            // Duration must be at least 75% of planned minimum
            let minDuration = Double(session.durationMinutes ?? 20) * 60 * 0.75
            return d.duration >= minDuration

        case (.aerobic(let d), .vo2Intervals),
             (.intervals(let d), .vo2Intervals):
            return d.intensity == .vigorous && d.duration >= 20 * 60

        case (.aerobic, .recovery), (.intervals, .recovery):
            return true

        default:
            return false
        }
    }

    private static func coachModalityFromAerobic(_ m: AerobicEventDetails.Modality) -> CoachSession.AerobicModality {
        switch m {
        case .running: return .run
        case .walking: return .walk
        case .cycling: return .cycle
        case .swimming: return .swim
        case .rowing: return .row
        case .boxing: return .boxing
        case .hiit, .other: return .other
        }
    }

    private static func describeCompletedEvent(_ event: TrainingEvent) -> String {
        switch event.kind {
        case .aerobic(let d), .intervals(let d):
            let mins = Int(d.duration / 60)
            return "\(d.modality.displayName) · \(mins) min logged today"
        case .strength:
            return "Strength session logged today"
        case .unknown:
            return "Workout logged today"
        }
    }

    private static func generateTomorrowPreview(facts: CoachFacts,
                                                  candidates: [CoachSession]) -> String? {
        let balance = facts.weeklyBalance
        let strengthFloor = 2
        let aerobicFloor = 150.0

        let strengthNeeded = balance.strengthDays < strengthFloor
        let aerobicNeeded = balance.moderateEquivalentMinutes < aerobicFloor

        // Check recovery gates for strength
        let canStrength: Bool
        if let wb = facts.recovery.wholeBody, facts.referenceDate.addingTimeInterval(86400) < wb.hardEligibleAt {
            canStrength = false
        } else {
            canStrength = true
        }

        if strengthNeeded && canStrength {
            return "Strength session"
        }

        if strengthNeeded && !canStrength {
            let hrs = facts.recovery.wholeBody.map { Int($0.hardEligibleAt.timeIntervalSince(facts.referenceDate) / 3600) } ?? 24
            return "Recovery — strength eligible in ~\(hrs)h"
        }

        if aerobicNeeded {
            return "Cardio session"
        }

        if balance.consecutiveHardDays >= 3 {
            return "Rest or easy recovery"
        }

        // Balanced: suggest a rest or easy day
        return "Rest or light activity"
    }

    // MARK: - Same-day repetition damping

    private static func sameDayDamping(for session: CoachSession,
                                         todayCompleted: [TrainingEvent]) -> Int {
        var penalty = 0
        for event in todayCompleted {
            switch event.kind {
            case .aerobic(let d), .intervals(let d):
                let eventMod = coachModalityFromAerobic(d.modality)
                if let sessionMod = session.modality, sessionMod == eventMod {
                    // Same modality completed today → penalize heavily
                    penalty += 40
                }
                if session.kind == .moderateAerobic || session.kind == .easyAerobic
                    || session.kind == .vo2Intervals {
                    // Any aerobic already done today → moderate penalty
                    penalty += 15
                }
            case .strength:
                if session.kind == .strength {
                    penalty += 40  // Strength already done today
                }
            case .unknown:
                penalty += 5
            }
        }
        return penalty
    }

    private static func score(_ candidates: [CoachSession], facts: CoachFacts,
                                profile: CoachPreferenceProfile,
                                todayCompleted: [TrainingEvent] = []) -> [CoachSession] {
        let balance = facts.weeklyBalance
        let strengthFloor = 2
        let aerobicFloor = 150.0

        return candidates.sorted { a, b in
            let baseA = scoreSessionBase(a, balance: balance, strengthFloor: strengthFloor, aerobicFloor: aerobicFloor)
            let baseB = scoreSessionBase(b, balance: balance, strengthFloor: strengthFloor, aerobicFloor: aerobicFloor)
            let prefA = profile.preferenceScore(for: a)
            let prefB = profile.preferenceScore(for: b)
            let dampenA = sameDayDamping(for: a, todayCompleted: todayCompleted)
            let dampenB = sameDayDamping(for: b, todayCompleted: todayCompleted)
            let scoreA = baseA + prefA - dampenA
            let scoreB = baseB + prefB - dampenB
            if scoreA != scoreB { return scoreA > scoreB }
            if a.isHard != b.isHard { return !a.isHard }
            return a.id < b.id
        }
    }

    private static func scoreSessionBase(_ session: CoachSession, balance: WeeklyBalance,
                                          strengthFloor: Int, aerobicFloor: Double) -> Int {
        var score = 0

        switch session.kind {
        case .strength:
            if balance.strengthDays < strengthFloor { score += 30 }
            if balance.moderateEquivalentMinutes >= aerobicFloor { score += 15 }
            score += 5
        case .moderateAerobic:
            if balance.moderateEquivalentMinutes < aerobicFloor { score += 35 }
            if balance.strengthDays >= strengthFloor { score += 10 }
            score += 5
        case .easyAerobic:
            if balance.moderateEquivalentMinutes < aerobicFloor { score += 25 }
            if balance.strengthDays >= strengthFloor { score += 10 }
            score += 5
        case .vo2Intervals:
            if balance.moderateEquivalentMinutes >= 50 && balance.strengthDays >= strengthFloor { score += 20 }
            score += 3
        case .recovery:
            if balance.consecutiveHardDays >= 3 { score += 40 }
            score += 2
        case .rest:
            if balance.consecutiveHardDays >= 4 { score += 45 }
            score += 1
        case .assessment:
            score += 1
        }

        return score
    }

    private static func generateWarnings(facts: CoachFacts) -> [CoachWarning] {
        var warnings: [CoachWarning] = []

        if facts.weeklyBalance.consecutiveHardDays >= 6 {
            warnings.append(CoachWarning(
                id: "consecutiveHardDays",
                message: "You've trained hard \(facts.weeklyBalance.consecutiveHardDays) days in a row. Evidence suggests recovery periods improve long-term adaptation.",
                citationIds: ["meeusenOvertraining2013"]
            ))
        }

        let setsByPart = facts.weeklyBalance.fractionalSets
        for (part, sets) in setsByPart where sets > 20 {
            warnings.append(CoachWarning(
                id: "excessiveWeeklyVolume.\(part.rawValue)",
                message: "\(part.displayName) has \(Int(sets)) sets this week — well above the research-backed starting range. Diminishing returns are likely.",
                citationIds: ["pellandDoseResponse2026"]
            ))
        }

        for event in facts.rolling7dCompletedEvents {
            guard case .strength(let details) = event.kind, let d = details else { continue }
            for ex in d.exercises where ex.hardSetCount > 10 {
                warnings.append(CoachWarning(
                    id: "excessiveSetsPerSession.\(ex.exerciseName)",
                    message: "\(ex.exerciseName) had \(ex.hardSetCount) hard sets in one session. Research found no advantage beyond ~5 hard sets per muscle per session.",
                    citationIds: ["amirthalingamGVT"]
                ))
            }
        }

        return warnings
    }

    private static func formatRelative(_ date: Date, _ now: Date) -> String {
        let mins = Int(now.timeIntervalSince(date) / 60)
        if mins < 120 { return "\(mins)m ago" }
        let hrs = mins / 60
        if hrs < 48 { return "\(hrs)h ago" }
        return "\(hrs / 24)d ago"
    }
}
