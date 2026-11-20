import CadenceFeatures
import Foundation
import CadenceCore

/// Fills planned working loads before the user starts a workout, using the same
/// cascade as set entry: an exact rep-match from history first, then an inverse
/// e1RM estimate from the best recent set, then the performer's literal last
/// working weight. Explicit loads, percentages and bodyweight sets are kept.
public enum PlanWeightSeeder {
    public static func fillMissingLoads(_ sets: [EditableSet],
                                        history: PartnerPlanResolver.ExerciseHistory,
                                        formula: OneRepMaxFormula = .epley) -> [EditableSet] {
        let samples = historySamples(history)
        let lastWeight = history.lastSets.last(where: { $0.reps > 0 && $0.weightKg > 0 })?.weightKg
            ?? history.firstWorkingWeightKg
        return sets.map { original in
            guard original.targetWeight == nil, original.loadMode == .straight else { return original }
            var set = original
            if let suggestion = WeightSuggestion.suggest(targetReps: set.targetReps,
                                                         history: samples,
                                                         formula: formula) {
                set.targetWeight = suggestion.weightKg
            } else if let lastWeight, lastWeight > 0 {
                set.targetWeight = lastWeight
            }
            return set
        }
    }

    public static func fill(plan: EditablePlan,
                            formula: OneRepMaxFormula = .epley,
                            history: (String, UUID?) -> PartnerPlanResolver.ExerciseHistory)
    -> EditablePlan {
        var updated = plan
        for index in updated.exercises.indices {
            let name = updated.exercises[index].name
            updated.exercises[index].sets = fillMissingLoads(
                updated.exercises[index].sets,
                history: history(name, nil),
                formula: formula)
            for planIndex in updated.exercises[index].performerPlans.indices {
                let performerID = updated.exercises[index].performerPlans[planIndex].performerID
                guard performerID != nil else { continue }
                updated.exercises[index].performerPlans[planIndex].sets = fillMissingLoads(
                    updated.exercises[index].performerPlans[planIndex].sets,
                    history: history(name, performerID),
                    formula: formula)
            }
        }
        return updated
    }

    /// Converts the compact history into dated samples. Recent sets get later
    /// dates so `WeightSuggestion`'s exact-rep recency rule matches "last time".
    private static func historySamples(_ history: PartnerPlanResolver.ExerciseHistory) -> [SetSample] {
        let base = Date(timeIntervalSince1970: 0)
        var samples = history.lastSets.enumerated().map { index, set in
            SetSample(weight: set.weightKg,
                      reps: set.reps,
                      date: base.addingTimeInterval(Double(index)),
                      isWarmup: false)
        }
        if samples.isEmpty, let weight = history.firstWorkingWeightKg, weight > 0 {
            samples = (history.repLadders.last ?? []).filter { $0 > 0 }.enumerated().map { index, reps in
                SetSample(weight: weight,
                          reps: reps,
                          date: base.addingTimeInterval(Double(index)),
                          isWarmup: false)
            }
        }
        return samples
    }
}
