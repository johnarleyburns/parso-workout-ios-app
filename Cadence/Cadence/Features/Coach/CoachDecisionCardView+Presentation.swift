import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension CoachDecisionCardView {
    var isCompleteState: Bool {
        if case .planComplete = decision.planAdherence { return true }
        return false
    }

    /// The coach's transparent full-body-vs-split explanation for the primary
    /// strength session, when one is being recommended (open-door principle).
    var sessionStructureFact: ObservedFact? {
        decision.observedFacts.first { $0.kind == .sessionStructure }
    }

    var todayCompleteDescription: String {
        if case .planComplete(_, let desc, _) = decision.planAdherence { return desc }
        return ""
    }

    var planAdherenceCompletedKind: CoachSessionKind? {
        if case .planComplete(let kind, _, _) = decision.planAdherence { return kind }
        return nil
    }

    var stateKind: String {
        if isCompleteState { return "PLAN DONE" }
        if remainingPlannedRecommendation?.isAerobic == true { return "AEROBIC" }
        switch decision.primary.kind {
        case .rest: return "RECOVERY"
        case .recovery: return "RECOVERY"
        case .easyAerobic: return hasRecentStrength ? "RECOVERY" : "AEROBIC"
        case .moderateAerobic: return "AEROBIC"
        case .vo2Intervals: return "AEROBIC"
        default: return "TRAIN"
        }
    }

    var stateIcon: String {
        if isCompleteState { return "checkmark.seal.fill" }
        switch decision.primary.kind {
        case .rest, .recovery: return "moon.zzz.fill"
        case .easyAerobic, .moderateAerobic: return "heart.fill"
        default: return "figure.mind.and.body"
        }
    }

    var stateColor: Color {
        if isCompleteState { return .green }
        switch decision.primary.kind {
        case .rest, .recovery: return .orange
        case .easyAerobic, .moderateAerobic, .vo2Intervals: return .teal
        default: return .green
        }
    }

    var heroContent: CoachHeroPresenter.Content {
        let adherence = decision.planAdherence
        let isComplete: Bool
        let completedKind: CoachSessionKind?
        let completedDesc: String?
        switch adherence {
        case .planAhead, .offPlan:
            isComplete = false; completedKind = nil; completedDesc = nil
        case .planComplete(let kind, let desc, _):
            isComplete = true; completedKind = kind; completedDesc = desc
        }
        let recent = decision.observedFacts.first.map { "\($0.title): \($0.value)" } ?? ""
        return CoachHeroPresenter.present(
            primaryKind: decision.primary.kind,
            primaryTitle: decision.primary.title,
            primarySubtitle: decision.primary.subtitle,
            todayPlannedCount: decision.todayPlannedRecommendations.count,
            isCompleteState: isComplete,
            planAdherenceCompletedKind: completedKind,
            completedDescription: completedDesc,
            recentFactText: recent,
            hasTodayStrengthCompleted: hasTodayStrengthCompleted,
            todayLoggedExerciseNames: todayLoggedExerciseNames)
    }

    var heroTitle: String { heroContent.title }
    var heroSubtitle: String { heroContent.subtitle }

    var recoveryChips: [(String, String)] {
        let deferredExercises = decision.deferred.compactMap { d -> String? in
            guard d.session.kind == .strength, let ex = d.session.exercises?.first else { return nil }
            return MuscleGroup.canonicalize(ex.primaryMuscles).first?.displayName
        }
        let unique = Array(Set(deferredExercises)).prefix(3)
        return unique.map { ($0, "recovering") }
    }

    var hasRecentStrength: Bool {
        decision.deferred.contains { $0.session.kind == .strength && !$0.reason.id.isEmpty }
    }

    var remainingPlannedRecommendation: CoachSession? {
        guard decision.todayPlannedRecommendations.count == 1 else { return nil }
        return decision.todayPlannedRecommendations.first
    }

    // MARK: - CTA

    var ctaLabel: String {
        // Every trainable recommendation reads "Start" and routes to that
        // workout's setup surface first (never an active recorder). Only rest /
        // recovery keep bespoke copy because they aren't a workout launch.
        switch decision.primary.kind {
        case .rest: return "Take a rest day"
        case .recovery: return "Start recovery"
        default: return "Start"
        }
    }

    var ctaSymbol: String {
        decision.primary.kind == .rest || decision.primary.kind == .recovery ? "moon.fill" : "play.fill"
    }

    /// "Pick another" is offered whenever the coach scored alternatives to swap
    /// to — the user can always redirect the prescription, whatever its kind
    /// (coach-user-control Phase 5 relaxed the old cardio-only gate).
    var showsAlternativesLink: Bool {
        !decision.alternatives.isEmpty
    }

    /// "Strength anyway" appears when today's coach output carries no strength
    /// at all — the coach suggests, it does not proscribe: the user can always
    /// ask for a strength session and peruse it in the plan editor.
    var showsStrengthAnywayLink: Bool {
        guard !isCompleteState else { return false }
        let offered = [decision.primary] + decision.alternatives + decision.todayPlannedRecommendations
        return !offered.contains { $0.kind == .strength }
    }

    var nextEligibleTime: String? {
        guard hasRecentStrength else { return nil }
        let reason = decision.deferred.first { $0.session.kind == .strength }?.reason.message
        return reason
    }

    // MARK: - Two-a-day stack

    var twoADayStack: some View {
        CoachTwoADayStack(sessions: decision.todayPlannedRecommendations,
                          onStart: onStart,
                          onSwap: onSwapComponent)
    }
}
