import Foundation

/// Foundation-only set-count and load arithmetic used by the production plan
/// optimizer. Inputs are plain value types keyed by muscle-group identifier; the
/// Core adapter maps app types to/from these. Pure and deterministic: no clock,
/// no randomness, ties break on an explicit caller-supplied order.
public enum PlanningSetAllocator {
    /// Sets to prescribe for one exercise.
    /// - Parameters:
    ///   - requestedSets: the exercise's authored sets, if any.
    ///   - perSetContribution: weighted sets one set adds per muscle group.
    ///   - deficits: remaining weekly deficit per group (empty = no deficit mode).
    ///   - projected: projected weekly volume per group so far.
    ///   - mrv: MRV ceiling per group (consulted only when `policy.respectsMRVCeiling`).
    public static func plannedSets(requestedSets: Int?,
                                   desiredSetsPerExercise: Int,
                                   perSetContribution: [String: Double],
                                   deficits: [String: Double],
                                   projected: [String: Double],
                                   mrv: [String: Double],
                                   policy: PlanningPolicy) -> Int {
        guard !deficits.isEmpty else {
            return min(policy.maxSetsPerExercise, max(2, requestedSets ?? desiredSetsPerExercise))
        }
        guard perSetContribution.contains(where: { deficits[$0.key] != nil && $0.value > 0 }) else { return 0 }
        var needed = 1
        for (group, amount) in deficits {
            guard let contribution = perSetContribution[group], contribution > 0 else { continue }
            needed = max(needed, Int(ceil(amount / contribution)))
        }
        var safe = policy.maxSetsPerExercise
        if policy.respectsMRVCeiling {
            for (group, contribution) in perSetContribution where contribution > 0 {
                let remaining = (mrv[group] ?? 0) - (projected[group] ?? 0)
                safe = min(safe, Int(floor(max(0, remaining) / contribution)))
            }
        }
        let desired = max(requestedSets ?? desiredSetsPerExercise, needed)
        return min(policy.maxSetsPerExercise, max(0, safe), max(1, desired))
    }

    /// Rounds a computed load to the nearest half unit; non-positive means "no load".
    public static func roundedLoad(_ suggested: Double) -> Double? {
        suggested > 0 ? (suggested * 2).rounded() / 2 : nil
    }

    /// Deficit ordering: largest deficit first, ties by explicit canonical index.
    public static func deficitOrdered(_ deficits: [String: Double],
                                      canonicalIndex: (String) -> Int) -> [String] {
        deficits.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            let (l, r) = (canonicalIndex(lhs.key), canonicalIndex(rhs.key))
            return l != r ? l < r : lhs.key < rhs.key
        }.map(\.key)
    }

    /// Whether hard strength work may be planned on a day.
    public static func hardStrengthAllowed(isRestDay: Bool,
                                           plannedMiddayTime: Date,
                                           wholeBodyHardEligibleAt: Date?,
                                           policy: PlanningPolicy) -> Bool {
        if policy.respectsRestDays && isRestDay { return false }
        if policy.respectsRecoveryEligibility, let eligible = wholeBodyHardEligibleAt,
           plannedMiddayTime < eligible { return false }
        return true
    }
}
