import Foundation

/// Phase G (field-test-fixes): per-rep-count weight autofill + inverse-e1RM.
/// Given a target rep count, suggests a weight based on the user's history using
/// either an exact rep-match or inverse Epley/Brzycki from their best recent set.
public enum WeightSuggestion {

    public enum Basis: Equatable {
        case exactRepMatch
        case estimatedFromE1RM
    }

    public struct Result: Equatable {
        public let weightKg: Double
        public let basis: Basis
        public let citationIds: [String]

        public init(weightKg: Double, basis: Basis, citationIds: [String] = []) {
            self.weightKg = weightKg
            self.basis = basis
            self.citationIds = citationIds
        }
    }

    /// Suggests a weight for the given target reps based on set history.
    /// - Exact rep-match (most recent) wins.
    /// - Falls back to inverse e1RM from the best recent working set.
    /// - Returns nil if no history is available.
    public static func suggest(
        targetReps: Int,
        history: [SetSample],
        formula: OneRepMaxFormula = .epley
    ) -> Result? {
        guard targetReps > 0 else { return nil }

        let working = history.filter { !$0.isWarmup && $0.reps > 0 && $0.weight > 0 }

        // 1. Exact rep-match: most recent set at this rep count.
        if let exact = working.first(where: { $0.reps == targetReps }) {
            return Result(weightKg: exact.weight, basis: .exactRepMatch)
        }

        // 2. e1RM from best recent set, then inverse formula.
        guard !working.isEmpty else { return nil }

        let best = working.max { a, b in
            let e1rmA = estimatedMax(weightKg: a.weight, reps: a.reps, formula: formula)
            let e1rmB = estimatedMax(weightKg: b.weight, reps: b.reps, formula: formula)
            return e1rmA < e1rmB
        }
        guard let best = best else { return nil }

        let e1rm = estimatedMax(weightKg: best.weight, reps: best.reps, formula: formula)
        let suggested = inverseE1RM(e1rm: e1rm, reps: targetReps, formula: formula)

        return Result(
            weightKg: suggested,
            basis: .estimatedFromE1RM,
            citationIds: [CitationRegistry.oneRMEstimation.id]
        )
    }

    // MARK: - Internal formulas

    /// Epley: e1RM = w × (1 + r/30)
    /// Brzycki: e1RM = w × (36 / (37 − r))
    static func estimatedMax(weightKg: Double, reps: Int, formula: OneRepMaxFormula) -> Double {
        guard reps > 0, weightKg > 0 else { return 0 }
        let r = Double(reps)
        switch formula {
        case .epley:
            return weightKg * (1 + r / 30.0)
        case .brzycki:
            guard r < 37 else { return weightKg }
            return weightKg * (36.0 / (37.0 - r))
        }
    }

    /// Inverse — given e1RM and target reps, what weight?
    /// Epley:  w = e1RM / (1 + r/30)
    /// Brzycki: w = e1RM × (1.0278 − 0.0278r)  (linear approximation)
    ///          or more precisely: w = e1RM × (37 − r) / 36
    static func inverseE1RM(e1rm: Double, reps: Int, formula: OneRepMaxFormula) -> Double {
        guard reps > 0, e1rm > 0 else { return 0 }
        let r = Double(reps)
        switch formula {
        case .epley:
            return e1rm / (1.0 + r / 30.0)
        case .brzycki:
            guard r < 37 else { return 0 }
            return e1rm * (37.0 - r) / 36.0
        }
    }
}
