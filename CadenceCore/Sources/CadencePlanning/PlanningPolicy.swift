import Foundation

/// Tunable guardrails the plan optimizer respects. `.safe` is the coach's default
/// (never plans back-to-back hard days, caps session size, stays under MRV, honors
/// rest days). `.meetDeficits` is the user-invoked "ignore constraints and plan to
/// meet my weekly deficits" override: it relaxes those guardrails so the week's
/// volume targets can actually be closed even at the cost of consecutive strength
/// days, oversized sessions, and exceeding MRV.
public struct PlanningPolicy: Sendable, Equatable {
    public var maxSetsPerExercise: Int
    public var maxExercisesPerSession: Int
    public var maxTotalSetsPerSession: Int
    public var maxExtraStrengthSlots: Int
    /// When true, hard strength work is blocked while the whole-body recovery
    /// window is still open.
    public var respectsRecoveryEligibility: Bool
    /// When true, strength work is never planned on the user's rest days.
    public var respectsRestDays: Bool
    /// When true, per-exercise set counts are capped so projected volume stays at
    /// or below MRV.
    public var respectsMRVCeiling: Bool
    /// When true, extra (added) strength slots are only created if the user allows
    /// two-a-days; when false the override may add slots regardless.
    public var requiresTwoADayPreferenceForExtraSlots: Bool

    public init(maxSetsPerExercise: Int,
                maxExercisesPerSession: Int,
                maxTotalSetsPerSession: Int,
                maxExtraStrengthSlots: Int,
                respectsRecoveryEligibility: Bool,
                respectsRestDays: Bool,
                respectsMRVCeiling: Bool,
                requiresTwoADayPreferenceForExtraSlots: Bool) {
        self.maxSetsPerExercise = maxSetsPerExercise
        self.maxExercisesPerSession = maxExercisesPerSession
        self.maxTotalSetsPerSession = maxTotalSetsPerSession
        self.maxExtraStrengthSlots = maxExtraStrengthSlots
        self.respectsRecoveryEligibility = respectsRecoveryEligibility
        self.respectsRestDays = respectsRestDays
        self.respectsMRVCeiling = respectsMRVCeiling
        self.requiresTwoADayPreferenceForExtraSlots = requiresTwoADayPreferenceForExtraSlots
    }

    /// The coach's default guardrails. ~6 exercises / ~18 sets per session
    /// (4 compound + 2 isolation) fits whole-body weekly coverage for 2-3
    /// strength days; ~50-55 min.
    public static let safe = PlanningPolicy(
        maxSetsPerExercise: 4,
        maxExercisesPerSession: 6,
        maxTotalSetsPerSession: 18,
        maxExtraStrengthSlots: 1,
        respectsRecoveryEligibility: true,
        respectsRestDays: true,
        respectsMRVCeiling: true,
        requiresTwoADayPreferenceForExtraSlots: true)

    /// User opt-out: relax the guardrails to close the week's volume deficits.
    public static let meetDeficits = PlanningPolicy(
        maxSetsPerExercise: 8,
        maxExercisesPerSession: 12,
        maxTotalSetsPerSession: 60,
        maxExtraStrengthSlots: 7,
        respectsRecoveryEligibility: false,
        respectsRestDays: false,
        respectsMRVCeiling: false,
        requiresTwoADayPreferenceForExtraSlots: false)
}
