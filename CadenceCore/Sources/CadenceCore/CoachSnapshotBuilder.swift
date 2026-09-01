import Foundation

/// The full set of coach outputs Home renders, computed together so the expensive
/// pipeline (facts → decision → plan optimization → insights) runs **once** instead
/// of the ~8–10× redundant recomputation the old per-property getters caused. Home
/// caches this and rebuilds it off the render path (only when history or settings
/// change), which is what removed the 1–2s stall on every logged set.
public struct CoachSnapshot: Sendable {
    public let facts: TrainingFacts
    /// Phase F (field-test-fixes): the CoachFacts the builder already computes
    /// at line ~60. Exposed so YourWeekView and strengthAnyway can reuse the
    /// cached value instead of recomputing from scratch.
    public let coachFacts: CoachFacts
    public let insights: [Insight]
    public let recommendation: Recommendation
    public let decision: CoachDecision
    public let plan: WeeklyPlan
    public let behindPlan: Bool
    public let addOn: CoachAddOnRecommendation
    /// The fused readiness (self-report + passive HealthKit), when present.
    public let readiness: ReadinessSnapshot?
    /// The optimizer's output — planned sessions + unresolved deficits + diagnostics.
    /// Carried so the Your Plan screen can render per-part volume vs plan (§1).
    public let optimizedPlan: OptimizedCoachPlan
    /// DB++'s seven-day derived observation surface. Nil only when the bundled
    /// engine is unavailable; legacy facts remain the compatibility fallback.
    public let engineObservation: EngineObservationSnapshot?

    public init(facts: TrainingFacts, coachFacts: CoachFacts, insights: [Insight], recommendation: Recommendation,
                decision: CoachDecision, plan: WeeklyPlan, behindPlan: Bool,
                addOn: CoachAddOnRecommendation, readiness: ReadinessSnapshot? = nil,
                optimizedPlan: OptimizedCoachPlan = .empty,
                engineObservation: EngineObservationSnapshot? = nil) {
        self.facts = facts
        self.coachFacts = coachFacts
        self.insights = insights
        self.recommendation = recommendation
        self.decision = decision
        self.plan = plan
        self.behindPlan = behindPlan
        self.addOn = addOn
        self.readiness = readiness
        self.optimizedPlan = optimizedPlan
        self.engineObservation = engineObservation
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
                             userAge: Int? = nil,
                             now: Date = Date(),
                             constraintPolicy: PlanningConstraintPolicy = .safe) -> CoachSnapshot {
        let liveSessions = sessions.filter { $0.deletedAt == nil }
        let trainingFacts = TrainingFacts.make(sessions: liveSessions,
                                               assessments: assessments,
                                               now: now,
                                               goal: goal,
                                               experience: experience,
                                               formula: formula)
        let events = trainingEvents(sessions: liveSessions, cardio: cardio,
                                    assessments: assessments, formula: formula,
                                    userAge: userAge)
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

        let legacyDecision = applyingOptimizedStrength(base, optimizedPlan: optimized)
        let engineObservation = TrainingEngineBridge.observationSnapshot(
            from: liveSessions,
            trackedGroups: schedulePreferences.trackedMuscleGroups,
            experience: experience,
            subjectId: "cladiron-local",
            asOf: now)
        let engineSuggestion = TrainingEngineBridge.adaptiveCoachSession(
            from: liveSessions,
            schedule: schedulePreferences,
            goal: goal,
            experience: experience,
            subjectId: "cladiron-local",
            asOf: now,
            facts: coachFacts)
        let decision = applyingEngineSuggestion(
            legacyDecision,
            suggestion: engineSuggestion,
            facts: coachFacts,
            hasPainConcern: hasPainToday)
        let behindPlan: Bool = { if case .offPlan = decision.planAdherence { return true }; return false }()

        let insights = PlanAwareInsightEngine.run(
            completed: trainingFacts,
            plan: plan,
            plannedStrengthSessions: optimized.plannedStrengthSessions,
            unresolvedDeficits: optimized.unresolvedDeficits,
            diagnostics: optimized.diagnostics,
            isBehindPlan: behindPlan,
            now: now,
            isOverrideActive: constraintPolicy == .meetDeficits)
        // "You already trained hard today" is an observation, not a prescription —
        // surfaced first so the Coach card's top insight acknowledges banked work
        // instead of nagging (coach-user-control Phase 2).
        let allInsights: [Insight]
        if let sameDay = SameDayLoadInsight.insight(facts: coachFacts) {
            allInsights = [sameDay] + insights
        } else {
            allInsights = insights
        }

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

        return CoachSnapshot(facts: trainingFacts, coachFacts: coachFacts,
                             insights: allInsights,
                             recommendation: recommendation, decision: decision,
                             plan: plan, behindPlan: behindPlan, addOn: addOn,
                             readiness: coachFacts.readiness, optimizedPlan: optimized,
                             engineObservation: engineObservation)
    }

    /// Off-main-actor variant: the caller pre-computes `TrainingFacts` and
    /// `TrainingEvent`s (on the main actor where SwiftData models are safe to read)
    /// and passes them here; the rest of the pipeline runs in a background task.
    public static func buildFromFactsAndEvents(
        trainingFacts: TrainingFacts,
        trainingEvents: [TrainingEvent],
        hasPainToday: Bool,
        goal: TrainingGoal,
        experience: ExperienceLevel,
        formula: OneRepMaxFormula,
        schedulePreferences: CoachSchedulePreferences,
        profile: CoachPreferenceProfile,
        readinessSnapshot: ReadinessSnapshot? = nil,
        passiveSamples: [PassiveReadinessSample] = [],
        now: Date = Date(),
        constraintPolicy: PlanningConstraintPolicy = .safe,
        engineObservation: EngineObservationSnapshot? = nil,
        engineSuggestion: CoachSession? = nil
    ) -> CoachSnapshot {
        let coachFacts = CoachFacts.make(from: trainingEvents, goal: goal, experience: experience,
                                          readinessSnapshot: readinessSnapshot,
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
            candidates: candidates,
            constraintPolicy: constraintPolicy)

        let legacyDecision = applyingOptimizedStrength(base, optimizedPlan: optimized)
        let decision = applyingEngineSuggestion(
            legacyDecision,
            suggestion: engineSuggestion,
            facts: coachFacts,
            hasPainConcern: hasPainToday)
        let behindPlan: Bool = { if case .offPlan = decision.planAdherence { return true }; return false }()

        let insights = PlanAwareInsightEngine.run(
            completed: trainingFacts,
            plan: plan,
            plannedStrengthSessions: optimized.plannedStrengthSessions,
            unresolvedDeficits: optimized.unresolvedDeficits,
            diagnostics: optimized.diagnostics,
            isBehindPlan: behindPlan,
            now: now,
            isOverrideActive: constraintPolicy == .meetDeficits)

        let allInsights: [Insight]
        if let sameDay = SameDayLoadInsight.insight(facts: coachFacts) {
            allInsights = [sameDay] + insights
        } else {
            allInsights = insights
        }

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

        return CoachSnapshot(facts: trainingFacts, coachFacts: coachFacts,
                             insights: allInsights,
                             recommendation: recommendation, decision: decision,
                             plan: plan, behindPlan: behindPlan, addOn: addOn,
                             readiness: coachFacts.readiness, optimizedPlan: optimized,
                             engineObservation: engineObservation)
    }

    // MARK: - Helpers (ported verbatim from HomeView so behavior is unchanged)

    public static func trainingEvents(sessions: [WorkoutSession], cardio: [CardioWorkout],
                               assessments: [Assessment], formula: OneRepMaxFormula,
                               userAge: Int? = nil) -> [TrainingEvent] {
        let strength = sessions.compactMap { TrainingEvent.from(session: $0, formula: formula) }
        let cardioEvents = cardio.filter { $0.deletedAt == nil }.map { TrainingEvent.from(cardio: $0, userAge: userAge) }
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

    /// Composes the engine's proposal after the app's existing optimization and
    /// safety layers. A deferred/blocked proposal is intentionally ignored so
    /// the legacy decision still owns lighter, recovery, and rest behavior.
    static func applyingEngineSuggestion(_ decision: CoachDecision,
                                         suggestion: CoachSession?,
                                         facts: CoachFacts,
                                         hasPainConcern: Bool) -> CoachDecision {
        guard let suggestion, !hasPainConcern else { return decision }
        guard case .eligible = SessionEligibilityPolicy.evaluate(suggestion, facts: facts)
        else { return decision }

        var primary = decision.primary
        var planned = decision.todayPlannedRecommendations
        if primary.kind == .strength {
            primary = suggestion
        }
        if let index = planned.firstIndex(where: { $0.kind == .strength }) {
            planned[index] = suggestion
        } else if primary.kind == .strength && planned.isEmpty {
            planned = [suggestion]
        }

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
            citationIds: Array(Set(decision.citationIds + suggestion.citationIds)).sorted(),
            planAdherence: decision.planAdherence,
            todayCompletedMatches: decision.todayCompletedMatches,
            scoreBreakdowns: decision.scoreBreakdowns,
            todayPlannedRecommendations: planned)
    }
}
