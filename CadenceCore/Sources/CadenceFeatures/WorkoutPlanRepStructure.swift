import Foundation

extension EditablePlan {
    public func repStructure(performerID: UUID?) -> [Int] {
        guard let exercise = exercises.first else { return [] }
        let sets = performerID == nil ? exercise.sets
            : (exercise.performerPlans.first { $0.performerID == performerID }?.sets ?? [])
        return sets.map(\.targetReps)
    }

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
