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
    public let scoreBreakdowns: [String: SessionScoreBreakdown]
    /// Every uncompleted planned workout for today (strength + cardio two-a-days).
    /// When today's plan includes both strength and cardio, both appear here.
    /// Completed session kinds are filtered out. Empty when plan is complete.
    public let todayPlannedRecommendations: [CoachSession]

    public init(id: String, generatedAt: Date, primary: CoachSession,
                alternatives: [CoachSession] = [], deferred: [DeferredCandidate] = [],
                warnings: [CoachWarning] = [], observedFacts: [ObservedFact] = [],
                weeklyBalance: WeeklyBalance, confidence: FactConfidence,
                citationIds: [String] = [],
                planAdherence: PlanAdherence = .planAhead,
                todayCompletedMatches: [CoachSession] = [],
                scoreBreakdowns: [String: SessionScoreBreakdown] = [:],
                todayPlannedRecommendations: [CoachSession] = []) {
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
        self.scoreBreakdowns = scoreBreakdowns
        self.todayPlannedRecommendations = todayPlannedRecommendations
    }
}

public struct DeferredCandidate: Sendable, Equatable, Identifiable {
    public let session: CoachSession
    public let reason: DecisionReason
    public var id: String { session.id }
}

/// Transparent, additive breakdown of how a candidate was ranked (P4). The base
/// term carries the existing strength/aerobic-floor logic; `systemNeed` is a small,
/// capped nudge so a stale system can break a near-tie without overriding the floors
/// or a user's modality preference.
public struct SessionScoreBreakdown: Sendable, Equatable {
    public let sessionId: String
    public let base: Int
    public let systemNeed: Int
    public let preference: Int
    public let sameDayPenalty: Int
    public let confidencePenalty: Int
    public let reasons: [EvidenceClaim]

    public init(sessionId: String, base: Int, systemNeed: Int, preference: Int,
                sameDayPenalty: Int, confidencePenalty: Int, reasons: [EvidenceClaim] = []) {
        self.sessionId = sessionId
        self.base = base
        self.systemNeed = systemNeed
        self.preference = preference
        self.sameDayPenalty = sameDayPenalty
        self.confidencePenalty = confidencePenalty
        self.reasons = reasons
    }

    public var total: Int { base + systemNeed + preference - sameDayPenalty - confidencePenalty }
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
                           schedulePreferences: CoachSchedulePreferences = .default,
                           hasPainConcern: Bool = false,
                           anaerobicOptIn: Bool = false) -> CoachDecision {
        let now = facts.referenceDate
        let candidates = CoachSession.candidates(for: facts, anaerobicOptIn: anaerobicOptIn)
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

        // Gate 3: score eligible candidates (base + system need + preference
        // − same-day damping − confidence penalty).
        let scored = score(eligible, facts: facts, profile: profile,
                           schedulePreferences: schedulePreferences,
                           todayCompleted: todayCompleted)

        let primary: CoachSession
        if let top = scored.first {
            primary = top.session
        } else {
            primary = candidates.first { $0.kind == .rest } ?? CoachSession(
                id: "rest.fallback", kind: .rest, title: "Rest day",
                subtitle: "No eligible training candidates right now.", launchPayload: .rest)
        }

        let alternatives = Array(scored.dropFirst().prefix(3)).map(\.session)
        let breakdownMap = Dictionary(scored.map { ($0.session.id, $0.breakdown) },
                                      uniquingKeysWith: { first, _ in first })

        // Two-a-day recommendations: collect the best uncompleted strength + cardio
        // candidates for today. The Coach card shows all of them stacked.
        let todayRecommendations = buildTodayRecommendations(
            scored: scored, todayCompleted: todayCompleted,
            facts: facts, schedulePreferences: schedulePreferences)

        // When today has planned recommendations, use the first uncompleted one
        // as primary only if the scored primary's kind is already done today.
        // Otherwise the scored primary (highest-scored candidate) stays.
        let effectivePrimary: CoachSession
        if let first = todayRecommendations.first {
            let primaryKindDone: Bool = {
                switch primary.kind {
                case .strength: return todayCompleted.contains { $0.isStrength }
                case .easyAerobic, .moderateAerobic, .vo2Intervals:
                    return todayCompleted.contains { $0.isAerobic }
                default: return false
                }
            }()
            effectivePrimary = primaryKindDone ? first : primary
        } else {
            effectivePrimary = primary
        }

        // Gate 4: Plan adherence — check if today's planned session is already done.
        // Uses effectivePrimary so two-a-day completion is correctly detected.
        let planState = computePlanAdherence(primary: effectivePrimary, todayCompleted: todayCompleted,
                                                candidates: candidates, facts: facts,
                                                schedulePreferences: schedulePreferences)

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
            value: "\(facts.weeklyBalance.strengthDays) / \(schedulePreferences.strengthDaysPerWeek)+",
            detail: "Target is \(schedulePreferences.strengthDaysPerWeek) or more"
        ))

        factsList.append(ObservedFact(
            kind: .weeklyModerateEquivalentMinutes,
            title: "Moderate-equivalent minutes",
            value: "\(Int(facts.weeklyBalance.moderateEquivalentMinutes)) / 150",
            detail: "Research-informed aerobic target"
        ))

        var allCitationIds = Set(effectivePrimary.citationIds)
        for w in warnings { allCitationIds.formUnion(w.citationIds) }

        let todayMatches = findTodayPlanMatches(primary: effectivePrimary, todayCompleted: todayCompleted, candidates: candidates)

        return CoachDecision(
            id: "decision.\(now.timeIntervalSince1970)",
            generatedAt: now,
            primary: effectivePrimary,
            alternatives: alternatives,
            deferred: deferred,
            warnings: warnings,
            observedFacts: factsList,
            weeklyBalance: facts.weeklyBalance,
            confidence: eligible.isEmpty ? .low : .moderate,
            citationIds: Array(allCitationIds),
            planAdherence: planState,
            todayCompletedMatches: todayMatches,
            scoreBreakdowns: breakdownMap,
            todayPlannedRecommendations: todayRecommendations
        )
    }

    // MARK: - Plan adherence

    private static func computePlanAdherence(primary: CoachSession,
                                                todayCompleted: [TrainingEvent],
                                                candidates: [CoachSession],
                                                facts: CoachFacts,
                                                schedulePreferences: CoachSchedulePreferences = .default) -> PlanAdherence {
        guard !todayCompleted.isEmpty else { return .planAhead }

        let strengthDone = todayCompleted.contains { event in
            candidates.contains { $0.kind == .strength && eventSatisfiesCoachSession(event, $0) }
        }
        let cardioDone = todayCompleted.contains { event in
            candidates.contains { $0.isAerobic && eventSatisfiesCoachSession(event, $0) }
        }

        let strengthNeeded = facts.weeklyBalance.strengthDays < schedulePreferences.strengthDaysPerWeek
        let cardioNeeded = facts.weeklyBalance.moderateEquivalentMinutes < 150.0

        // When both strength and cardio are weekly-needed, require both to be
        // completed before the day is done. If only one is done, stay planAhead
        // so the remaining recommendation stays visible on the Coach card.
        if strengthNeeded && cardioNeeded {
            if strengthDone && cardioDone {
                let tomorrowPreview = generateTomorrowPreview(facts: facts, candidates: candidates,
                                                               schedulePreferences: schedulePreferences)
                return .planComplete(completedKind: .strength,
                                      todayDescription: "Strength and cardio — both in the books",
                                      tomorrowPreview: tomorrowPreview)
            }
            return .planAhead
        }

        // Single-type needed: match any completed event against any candidate.
        var matchedSessions: [(event: TrainingEvent, session: CoachSession)] = []
        for event in todayCompleted {
            for candidate in candidates {
                if eventSatisfiesCoachSession(event, candidate) {
                    matchedSessions.append((event, candidate))
                }
            }
        }

        if !matchedSessions.isEmpty {
            let bestMatch = matchedSessions.first!
            let completedKind = bestMatch.session.kind
            let todayDescription = describeCompletedEvent(bestMatch.event)
            let tomorrowPreview = generateTomorrowPreview(facts: facts, candidates: candidates,
                                                           schedulePreferences: schedulePreferences)
            return .planComplete(completedKind: completedKind,
                                  todayDescription: todayDescription,
                                  tomorrowPreview: tomorrowPreview)
        }

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
            return "\(d.modality.displayName) · \(mins) min in the books"
        case .strength:
            return "You put in the work today"
        case .unknown:
            return "Workout in the books"
        }
    }

    private static func generateTomorrowPreview(facts: CoachFacts,
                                                  candidates: [CoachSession],
                                                  schedulePreferences: CoachSchedulePreferences = .default) -> String? {
        let balance = facts.weeklyBalance
        let strengthFloor = schedulePreferences.strengthDaysPerWeek
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
                                schedulePreferences: CoachSchedulePreferences = .default,
                                todayCompleted: [TrainingEvent] = [])
        -> [(session: CoachSession, breakdown: SessionScoreBreakdown)] {
        let balance = facts.weeklyBalance
        let strengthFloor = schedulePreferences.strengthDaysPerWeek
        let aerobicFloor = 150.0

        let scored = candidates.map { c -> (session: CoachSession, breakdown: SessionScoreBreakdown) in
            let base = scoreSessionBase(c, balance: balance, strengthFloor: strengthFloor, aerobicFloor: aerobicFloor)
            let need = systemNeed(for: c, facts: facts)
            let pref = profile.preferenceScore(for: c)
            let dampen = sameDayDamping(for: c, todayCompleted: todayCompleted)
            let confPenalty = confidencePenalty(for: c, facts: facts)
            let breakdown = SessionScoreBreakdown(
                sessionId: c.id, base: base, systemNeed: need, preference: pref,
                sameDayPenalty: dampen, confidencePenalty: confPenalty,
                reasons: systemNeedReasons(for: c, facts: facts, systemNeed: need))
            return (c, breakdown)
        }

        return scored.sorted { a, b in
            if a.breakdown.total != b.breakdown.total { return a.breakdown.total > b.breakdown.total }
            if a.session.isHard != b.session.isHard { return !a.session.isHard }
            return a.session.id < b.session.id
        }
    }

    /// Small, capped nudge (≤12) toward candidates that train a system the user has
    /// neglected this week or has no baseline for. Bounded well under the strength/
    /// aerobic floor terms so it breaks near-ties without overriding them, and it is
    /// constant across modalities of the same kind so it never disturbs a user's
    /// remembered modality preference.
    private static func systemNeed(for session: CoachSession, facts: CoachFacts) -> Int {
        guard !session.systemsTrained.isEmpty else { return 0 }
        let stale = Set(facts.staleSystems)
        var score = 0
        for sys in session.systemsTrained {
            if stale.contains(sys) { score += 8 }
            if facts.assessmentCoverage[sys].map({ !$0.hasBaseline }) ?? false { score += 4 }
        }
        return min(score, 12)
    }

    private static func systemNeedReasons(for session: CoachSession, facts: CoachFacts,
                                           systemNeed: Int) -> [EvidenceClaim] {
        guard systemNeed > 0, let category = session.evidenceCategory,
              let sys = session.systemsTrained.first else { return [] }
        return [EvidenceClaim(
            id: "systemNeed.\(session.id)",
            text: "\(sys.displayName) has had little work recently — training it now restores balance.",
            category: category, date: facts.referenceDate)]
    }

    /// HR-zone–dependent prescriptions (VO₂, threshold, anaerobic) are less certain
    /// when max-HR is only age-estimated. A small penalty, never a floor override.
    private static func confidencePenalty(for session: CoachSession, facts: CoachFacts) -> Int {
        let hrDependent = session.systemsTrained.contains(.vo2max)
            || session.systemsTrained.contains(.threshold)
            || session.systemsTrained.contains(.anaerobicPower)
        guard hrDependent else { return 0 }
        switch facts.zoneSource {
        case .tested: return 0
        case .ageEstimated: return 3
        case .unknown: return 5
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

    /// Builds the list of today's planned-but-uncompleted recommendations.
    /// Only populates when the user has enabled two-a-days AND both strength and
    /// cardio are needed. Single-type plans let the scored primary carry the
    /// recommendation alone.
    private static func buildTodayRecommendations(
        scored: [(session: CoachSession, breakdown: SessionScoreBreakdown)],
        todayCompleted: [TrainingEvent],
        facts: CoachFacts,
        schedulePreferences: CoachSchedulePreferences) -> [CoachSession] {

        // Only activate two-a-day recommendations when the user has opted in.
        guard schedulePreferences.allowsTwoADays else { return [] }

        let strengthDone = todayCompleted.contains { $0.isStrength }
        let cardioDone = todayCompleted.contains { $0.isAerobic }

        let strengthNeeded = facts.weeklyBalance.strengthDays < schedulePreferences.strengthDaysPerWeek
        let cardioNeeded = facts.weeklyBalance.moderateEquivalentMinutes < 150.0

        // Only build when both are needed (a two-a-day) and at least one remains.
        guard strengthNeeded && cardioNeeded else { return [] }
        guard !strengthDone || !cardioDone else { return [] }

        let bestStrength = scored.first { $0.session.kind == .strength }?.session
        let bestCardio = scored.first { $0.session.isAerobic }?.session

        var recommendations: [CoachSession] = []

        if let s = bestStrength, !strengthDone {
            recommendations.append(s)
        }
        if let c = bestCardio, !cardioDone {
            recommendations.append(c)
        }

        return recommendations
    }

    private static func formatRelative(_ date: Date, _ now: Date) -> String {
        let mins = Int(now.timeIntervalSince(date) / 60)
        if mins < 120 { return "\(mins)m ago" }
        let hrs = mins / 60
        if hrs < 48 { return "\(hrs)h ago" }
        return "\(hrs / 24)d ago"
    }
}
