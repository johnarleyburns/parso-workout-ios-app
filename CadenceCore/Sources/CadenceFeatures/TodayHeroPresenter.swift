import Foundation
import CadenceCore

public struct TodayHero: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case suggested, scheduled, inProgress, doneToday, restDay, needsHistory, loading }
    public struct Line: Equatable, Sendable {
        public let name: String
        public let detail: String
        public init(name: String, detail: String) { self.name = name; self.detail = detail }
    }
    public let kind: Kind
    public let title: String
    public let estimatedMinutes: Int?
    public let exercises: [Line]
    public let reason: String?
    public let citationIDs: [String]
    public let summary: DaySummary?
    public let computedAt: Date

    public init(kind: Kind, title: String, estimatedMinutes: Int? = nil,
                exercises: [Line] = [], reason: String? = nil,
                citationIDs: [String] = [], summary: DaySummary? = nil,
                computedAt: Date = Date()) {
        self.kind = kind; self.title = title; self.estimatedMinutes = estimatedMinutes
        self.exercises = Array(exercises.prefix(5)); self.reason = reason
        self.citationIDs = citationIDs; self.computedAt = computedAt
        self.summary = summary
    }
}

public enum TodayHeroPresenter {
    /// Preserve the actual modality; absence of a strength draft is not recovery.
    public static func recommendation(_ decision: CoachDecision, computedAt: Date = Date()) -> TodayHero {
        let session = decision.primary
        let isRecovery = session.kind == .rest || session.kind == .recovery
        let ranking = decision.scoreBreakdowns[session.id]?.reasons ?? []
        var reasons = ranking.map { $0.text }
        if isRecovery {
            reasons += decision.deferred.map { $0.reason.message }
            let hardDays = decision.weeklyBalance.consecutiveHardDays
            if hardDays >= 3 {
                reasons.append(String(localized: "You have logged \(hardDays) consecutive hard training days.", bundle: .module))
            }
            if let score = decision.scoreBreakdowns[session.id], score.preference > 0 {
                reasons.append(String(localized: "Your previous workout choices favor this option.", bundle: .module))
            }
            reasons += decision.observedFacts.filter {
                $0.kind == .lastStrength || $0.kind == .lastCardio
            }.map { "\($0.title): \($0.value)" }
        }
        if !isRecovery {
            let kind: ObservedFact.Kind = session.kind == .strength ? .weeklyStrengthDays : .weeklyModerateEquivalentMinutes
            reasons += decision.observedFacts.filter { $0.kind == kind }.map { "\($0.title): \($0.value)" }
        }
        let evidence = session.citationIds + ranking.map { $0.selectedCitationId } + (isRecovery ? decision.deferred.flatMap { $0.reason.citationIds } : [])
        let explanation = ([session.subtitle] + Array(Set(reasons)).sorted()).filter { !$0.isEmpty }.joined(separator: "\n")
        return TodayHero(kind: isRecovery ? .restDay : .suggested, title: session.title,
                         estimatedMinutes: session.durationMinutes,
                         exercises: (session.exercises ?? []).map { exercise in
                             let low = exercise.repsLow.map(String.init) ?? "—"
                             let reps = exercise.repsHigh.map { high in
                                 exercise.repsLow != high ? "\(low)–\(high)" : low
                             } ?? low
                             let sets = exercise.sets.map(String.init) ?? "—"
                             return TodayHero.Line(name: exercise.name, detail: "\(sets) × \(reps)")
                         }, reason: explanation.isEmpty ? nil : explanation,
                         citationIDs: Array(Set(evidence)).sorted(), computedAt: computedAt)
    }

    public static func hero(inProgress: TodayHero?, scheduled: TodayHero?, suggested: TodayHero?,
                            fallbackRecommendation: TodayHero? = nil,
                            completedWorkoutCount: Int, completedToday: DaySummary? = nil,
                            remainingScheduledToday: Int = 0,
                            recommendationReady: Bool = true,
                            computedAt: Date = Date()) -> TodayHero {
        if let inProgress { return inProgress.with(kind: .inProgress, computedAt: computedAt) }
        if let scheduled { return scheduled.with(kind: .scheduled, computedAt: computedAt) }
        if let completedToday, remainingScheduledToday == 0 {
            return TodayHero(kind: .doneToday, title: completedToday.title,
                             summary: completedToday, computedAt: computedAt)
        }
        if completedWorkoutCount < 2 {
            return TodayHero(kind: .needsHistory,
                             title: String(localized: "Log a workout and your coach will start suggesting.", bundle: .module),
                             computedAt: computedAt)
        }
        if !recommendationReady {
            return TodayHero(kind: .loading,
                             title: String(localized: "Checking today's plan…", bundle: .module),
                             computedAt: computedAt)
        }
        return (suggested ?? fallbackRecommendation
                ?? TodayHero(kind: .restDay, title: String(localized: "Recovery day", bundle: .module), computedAt: computedAt))
            .with(computedAt: computedAt)
    }
}

private extension TodayHero {
    func with(kind: Kind? = nil, computedAt: Date) -> TodayHero {
        TodayHero(kind: kind ?? self.kind, title: title, estimatedMinutes: estimatedMinutes,
                  exercises: exercises, reason: reason, citationIDs: citationIDs,
                  summary: summary, computedAt: computedAt)
    }
}

public struct DaySummary: Equatable, Sendable {
    public let title: String
    public let setCount: Int
    public let volumeKg: Double
    public let bestPR: String?
    public let durationMinutes: Int?
    public let nextSessionTitle: String?
    public let nextSessionDate: Date?

    public init(title: String, setCount: Int, volumeKg: Double, bestPR: String? = nil,
                durationMinutes: Int? = nil, nextSessionTitle: String? = nil,
                nextSessionDate: Date? = nil) {
        self.title = title
        self.setCount = setCount
        self.volumeKg = volumeKg
        self.bestPR = bestPR
        self.durationMinutes = durationMinutes
        self.nextSessionTitle = nextSessionTitle
        self.nextSessionDate = nextSessionDate
    }
}
