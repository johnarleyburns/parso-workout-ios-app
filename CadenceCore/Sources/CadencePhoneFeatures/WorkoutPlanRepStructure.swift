import CadenceFeatures
import Foundation
import CadenceWorkoutFeatures

/// The flat, equal-reps-per-set structures offered by the Workout Plan editor's
/// "Rep structure" sheet, and the roster summary line format ("Me: 8-8-8").
/// Distinct from `RepSchemePreset` (decreasing warm-up-to-work-set ladders used
/// by the older template picker).
public enum WorkoutPlanRepSchemeOptions {
    /// Sorted by number of sets, then by the first set's reps -- not a hand
    /// ordering, so a future addition never needs manual resorting.
    public static let common: [[Int]] = [
        [5, 5, 5, 5, 5], [8, 8, 8], [10, 10, 10], [12, 12, 12],
        [8, 8, 8, 8], [3, 3, 3, 3, 3], [20, 20, 20],
    ].sorted { a, b in
        a.count != b.count ? a.count < b.count : (a.first ?? 0) < (b.first ?? 0)
    }

    /// "Me: 8-8-8" / "Jordan: 8-8-8" -- the roster summary line for one performer.
    public static func summary(name: String, reps: [Int]) -> String {
        guard !reps.isEmpty else { return name }
        return "\(name): \(reps.map(String.init).joined(separator: "-"))"
    }

    /// A blank (load-less) set template following the plan's rep structure. The
    /// plan weight seeder fills each target load from the exercise's own history
    /// without collapsing the row back to a single historical set.
    public static func templateSets(following reps: [Int]) -> [EditableSet] {
        reps.map { EditableSet(targetReps: $0, targetWeight: nil) }
    }
}

extension EditablePlan {
    /// Apply only to the selected performer. Keep each exercise's existing loads
    /// and repeat its last load when the new structure adds working sets.
    public mutating func applyRepStructure(_ reps: [Int], performerID: UUID?) {
        guard !reps.isEmpty, reps.allSatisfy({ $0 > 0 && $0 <= 100 }) else { return }
        func updated(_ sets: [EditableSet]) -> [EditableSet] {
            reps.enumerated().map { index, reps in
                var set = sets.indices.contains(index) ? sets[index] : EditableSet(
                    targetReps: reps, targetWeight: sets.last?.targetWeight,
                    loadMode: sets.last?.loadMode ?? .straight,
                    oneRepMaxPercent: sets.last?.oneRepMaxPercent)
                set.targetReps = reps
                return set
            }
        }
        for index in exercises.indices {
            if performerID == nil { exercises[index].sets = updated(exercises[index].sets) }
            for person in exercises[index].performerPlans.indices
            where exercises[index].performerPlans[person].performerID == performerID {
                exercises[index].performerPlans[person].sets = performerID == nil
                    ? exercises[index].sets : updated(exercises[index].performerPlans[person].sets)
            }
        }
    }
}
