import Foundation

/// A minimal value representation of a set, so PR logic stays pure and
/// independently unit-testable (no SwiftData required).
public struct SetSample: Equatable, Sendable {
    public var weight: Double      // canonical kg
    public var reps: Int
    public var date: Date
    public var isWarmup: Bool

    public init(weight: Double, reps: Int, date: Date = Date(), isWarmup: Bool = false) {
        self.weight = weight
        self.reps = reps
        self.date = date
        self.isWarmup = isWarmup
    }
}

/// Personal-record math. Pure; operates on `SetSample` collections (FR-1.3/1.4, FR-5.2).
public enum PRCalculator {

    /// The metric value of a single set under the given rule.
    public static func metric(_ s: SetSample, rule: PRRule, formula: OneRepMaxFormula) -> Double {
        switch rule {
        case .topWeight:    return s.weight
        case .estimated1RM: return WorkoutMath.estimated1RM(weight: s.weight, reps: s.reps, formula: formula)
        case .topVolume:    return WorkoutMath.volume(weight: s.weight, reps: s.reps)
        }
    }

    /// Best PR value across the given sets (warmups ignored). Returns nil if none.
    public static func best(_ samples: [SetSample], rule: PRRule, formula: OneRepMaxFormula) -> Double? {
        let working = samples.filter { !$0.isWarmup && $0.reps > 0 && $0.weight > 0 }
        guard !working.isEmpty else { return nil }
        return working.map { metric($0, rule: rule, formula: formula) }.max()
    }

    /// The set that achieves the PR, if any.
    public static func bestSample(_ samples: [SetSample], rule: PRRule, formula: OneRepMaxFormula) -> SetSample? {
        let working = samples.filter { !$0.isWarmup && $0.reps > 0 && $0.weight > 0 }
        return working.max { metric($0, rule: rule, formula: formula) < metric($1, rule: rule, formula: formula) }
    }

    /// Whether `candidate` is a new PR given the prior history. A tie does NOT
    /// count as a new PR (must strictly exceed the previous best). With no prior
    /// history, any valid working set is a PR.
    public static func isNewPR(candidate: SetSample,
                               previous: [SetSample],
                               rule: PRRule,
                               formula: OneRepMaxFormula) -> Bool {
        guard !candidate.isWarmup, candidate.reps > 0, candidate.weight > 0 else { return false }
        let candidateValue = metric(candidate, rule: rule, formula: formula)
        guard let prior = best(previous, rule: rule, formula: formula) else { return true }
        return candidateValue > prior + 1e-9
    }
}
