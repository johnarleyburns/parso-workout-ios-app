import Foundation
import CadenceCore

/// The full set of coach outputs Home renders, computed together so the expensive
/// pipeline (facts → decision → plan optimization → insights over ALL history) runs
/// **once** instead of the ~8–10× redundant recomputation the old per-property
/// getters caused. Home caches this and rebuilds it off the render path (only when
/// history or settings change), which removed the 1–2s stall on every logged set.
struct HomeCoachSnapshot {
    var facts: TrainingFacts
    var coachFacts: CoachFacts
    var insights: [Insight]
    var recommendation: Recommendation
    var decision: CoachDecision
    var plan: WeeklyPlan
    var behindPlan: Bool
    var addOn: CoachAddOnRecommendation
    var readiness: ReadinessSnapshot?
    var optimizedPlan: OptimizedCoachPlan
    var engineObservation: EngineObservationSnapshot?

    init(_ s: CoachSnapshot) {
        facts = s.facts; coachFacts = s.coachFacts; insights = s.insights; recommendation = s.recommendation
        decision = s.decision; plan = s.plan; behindPlan = s.behindPlan; addOn = s.addOn
        readiness = s.readiness; optimizedPlan = s.optimizedPlan
        engineObservation = s.engineObservation
    }

    /// Cheap cold-start value shown for the first frame before `.task` computes the
    /// real snapshot (empty inputs → cold-start decision/recommendation).
    static let placeholder = HomeCoachSnapshot(
        CoachSnapshotBuilder.build(
            sessions: [], cardio: [], assessments: [], hasPainToday: false,
            goal: .strength, experience: .intermediate, formula: .epley,
            schedulePreferences: CoachSchedulePreferences(), profile: .empty))
}
