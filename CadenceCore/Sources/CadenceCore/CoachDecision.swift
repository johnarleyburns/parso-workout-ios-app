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

    public init(id: String, generatedAt: Date, primary: CoachSession,
                alternatives: [CoachSession] = [], deferred: [DeferredCandidate] = [],
                warnings: [CoachWarning] = [], observedFacts: [ObservedFact] = [],
                weeklyBalance: WeeklyBalance, confidence: FactConfidence,
                citationIds: [String] = []) {
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
                citationIds: ["meeusenOvertraining2013"]
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

        // Gate 3: score eligible candidates (base + preference adjustment)
        let scored = score(eligible, facts: facts, profile: profile)

        let primary: CoachSession
        if let top = scored.first {
            primary = top
        } else {
            primary = candidates.first { $0.kind == .rest } ?? CoachSession(
                id: "rest.fallback", kind: .rest, title: "Rest day",
                subtitle: "No eligible training candidates right now.", launchPayload: .rest)
        }

        let alternatives = Array(scored.dropFirst().prefix(3))

        // Generate warnings
        let warnings = generateWarnings(facts: facts)

        // Generate observed facts
        var factsList: [ObservedFact] = []

        if let lastStrength = facts.rolling72hCompletedEvents.last(where: { $0.isStrength }) {
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

        if let lastCardio = facts.rolling72hCompletedEvents.last(where: { $0.isAerobic }) {
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
            detail: "Public-health floor"
        ))

        var allCitationIds = Set(primary.citationIds)
        for w in warnings { allCitationIds.formUnion(w.citationIds) }

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
            citationIds: Array(allCitationIds)
        )
    }

    private static func score(_ candidates: [CoachSession], facts: CoachFacts,
                               profile: CoachPreferenceProfile) -> [CoachSession] {
        let balance = facts.weeklyBalance
        let strengthFloor = 2
        let aerobicFloor = 150.0

        return candidates.sorted { a, b in
            let baseA = scoreSessionBase(a, balance: balance, strengthFloor: strengthFloor, aerobicFloor: aerobicFloor)
            let baseB = scoreSessionBase(b, balance: balance, strengthFloor: strengthFloor, aerobicFloor: aerobicFloor)
            let prefA = profile.preferenceScore(for: a)
            let prefB = profile.preferenceScore(for: b)
            let scoreA = baseA + prefA
            let scoreB = baseB + prefB
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
