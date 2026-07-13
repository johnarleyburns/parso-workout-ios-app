import Foundation

/// The full set of coach outputs Home renders, computed together so the expensive
/// pipeline (facts → decision → plan optimization → insights) runs **once** instead
/// of the ~8–10× redundant recomputation the old per-property getters caused. Home
/// caches this and rebuilds it off the render path (only when history or settings
/// change), which is what removed the 1–2s stall on every logged set.
public struct CoachSnapshot: Sendable {
    public let facts: TrainingFacts
    public let insights: [Insight]
    public let recommendation: Recommendation
    public let decision: CoachDecision
    public let plan: WeeklyPlan
    public let behindPlan: Bool
    public let addOn: CoachAddOnRecommendation
    /// The fused readiness (self-report + passive HealthKit), when present.
    public let readiness: ReadinessSnapshot?

    public init(facts: TrainingFacts, insights: [Insight], recommendation: Recommendation,
                decision: CoachDecision, plan: WeeklyPlan, behindPlan: Bool,
                addOn: CoachAddOnRecommendation, readiness: ReadinessSnapshot? = nil) {
        self.facts = facts
        self.insights = insights
        self.recommendation = recommendation
        self.decision = decision
        self.plan = plan
        self.behindPlan = behindPlan
        self.addOn = addOn
        self.readiness = readiness
    }
}

/// Builds a `CoachSnapshot` from the user's history + coach settings. Pure and
/// headlessly `swift test`-verifiable — the UI just caches what this returns.
public enum CoachSnapshotBuilder {

    public static func build(sessions: [WorkoutSession],
                             cardio: [CardioWorkout],
                             assessments: [Assessment],
                             hasPainToday: Bool,
                             goal: TrainingGoal,
                             experience: ExperienceLevel,
                             formula: OneRepMaxFormula,
                             schedulePreferences: CoachSchedulePreferences,
                             profile: CoachPreferenceProfile,
                             readinessEntry: ReadinessEntry? = nil,
                             passiveSamples: [PassiveReadinessSample] = [],
                             now: Date = Date()) -> CoachSnapshot {
        let liveSessions = sessions.filter { $0.deletedAt == nil }
        let trainingFacts = TrainingFacts.make(sessions: liveSessions,
                                               assessments: assessments,
                                               now: now,
                                               goal: goal,
                                               experience: experience,
                                               formula: formula)
        let events = trainingEvents(sessions: liveSessions, cardio: cardio,
                                    assessments: assessments, formula: formula)
        let coachFacts = CoachFacts.make(from: events, goal: goal, experience: experience,
                                         readinessEntry: readinessEntry,
                                         formula: formula, now: now,
                                         passiveSamples: passiveSamples)
        let plan = WeeklyPlan.generate(from: coachFacts, schedulePreferences: schedulePreferences)

        let base = CoachDecisionEngine.run(coachFacts,
                                           profile: profile,
                                           schedulePreferences: schedulePreferences,
                                           hasPainConcern: hasPainToday)

        let candidates = strengthCandidates(for: base, facts: coachFacts,
                                            schedulePreferences: schedulePreferences)
        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: trainingFacts,
            coachFacts: coachFacts,
            weeklyPlan: plan,
            schedulePreferences: schedulePreferences,
            candidates: candidates)

        let decision = applyingOptimizedStrength(base, optimizedPlan: optimized)
        let behindPlan: Bool = { if case .offPlan = decision.planAdherence { return true }; return false }()

        let insights = PlanAwareInsightEngine.run(
            completed: trainingFacts,
            plan: plan,
            plannedStrengthSessions: optimized.plannedStrengthSessions,
            unresolvedDeficits: optimized.unresolvedDeficits,
            diagnostics: optimized.diagnostics,
            isBehindPlan: behindPlan,
            now: now)

        let recommendation: Recommendation = {
            if let rec = CoachRecommendationEngine.run(coachFacts, profile: profile)
                .first(where: { rec in
                    if let system = rec.system {
                        return [.maximalStrength, .hypertrophy, .strengthEndurance].contains(system)
                    }
                    return [.progression, .deload, .addVolume, .starter, .strengthBlock, .volumeAdjust].contains(rec.kind)
                }) {
                return rec
            }
            return RecommendationEngine.top(trainingFacts)
        }()

        let addOn: CoachAddOnRecommendation = {
            guard case .planComplete = decision.planAdherence else { return .empty }
            return CoachAddOnEngine.run(facts: coachFacts,
                                        schedulePreferences: schedulePreferences,
                                        hasPainConcern: hasPainToday)
        }()

        return CoachSnapshot(facts: trainingFacts, insights: insights,
                             recommendation: recommendation, decision: decision,
                             plan: plan, behindPlan: behindPlan, addOn: addOn,
                             readiness: coachFacts.readiness)
    }

    // MARK: - Helpers (ported verbatim from HomeView so behavior is unchanged)

    static func trainingEvents(sessions: [WorkoutSession], cardio: [CardioWorkout],
                               assessments: [Assessment], formula: OneRepMaxFormula) -> [TrainingEvent] {
        let strength = sessions.compactMap { TrainingEvent.from(session: $0, formula: formula) }
        let cardioEvents = cardio.filter { $0.deletedAt == nil }.map { TrainingEvent.from(cardio: $0) }
        let assessmentEvents = assessments.map { TrainingEvent.from(assessment: $0) }
        return strength + cardioEvents + assessmentEvents
    }

    static func strengthCandidates(for decision: CoachDecision, facts: CoachFacts,
                                   schedulePreferences: CoachSchedulePreferences) -> [CoachSession] {
        let engineCandidates = CoachSession.candidates(for: facts, schedulePreferences: schedulePreferences)
        var seen = Set<String>()
        return ([decision.primary] + decision.todayPlannedRecommendations + decision.alternatives + engineCandidates)
            .filter { session in
                guard session.kind == .strength, !((session.exercises ?? []).isEmpty) else { return false }
                return seen.insert(session.id).inserted
            }
    }

    static func applyingOptimizedStrength(_ decision: CoachDecision,
                                          optimizedPlan: OptimizedCoachPlan) -> CoachDecision {
        guard !optimizedPlan.plannedStrengthSessions.isEmpty else { return decision }

        var nextOptimized = optimizedPlan.plannedStrengthSessions.makeIterator()
        var optimizedToday: [CoachSession] = []
        for session in decision.todayPlannedRecommendations {
            if session.kind == .strength, let replacement = nextOptimized.next() {
                optimizedToday.append(replacement)
            } else {
                optimizedToday.append(session)
            }
        }

        var primary = decision.primary
        if primary.kind == .strength {
            primary = optimizedToday.first(where: { $0.kind == .strength })
                ?? optimizedPlan.plannedStrengthSessions.first
                ?? primary
        } else if optimizedToday.count == 1, let only = optimizedToday.first, only.kind == .strength {
            primary = only
        }

        let citationIds = Array(Set(decision.citationIds + primary.citationIds)).sorted()
        return CoachDecision(
            id: decision.id,
            generatedAt: decision.generatedAt,
            primary: primary,
            alternatives: decision.alternatives,
            deferred: decision.deferred,
            warnings: decision.warnings,
            observedFacts: decision.observedFacts,
            weeklyBalance: decision.weeklyBalance,
            confidence: decision.confidence,
            citationIds: citationIds,
            planAdherence: decision.planAdherence,
            todayCompletedMatches: decision.todayCompletedMatches,
            scoreBreakdowns: decision.scoreBreakdowns,
            todayPlannedRecommendations: optimizedToday)
    }
}
