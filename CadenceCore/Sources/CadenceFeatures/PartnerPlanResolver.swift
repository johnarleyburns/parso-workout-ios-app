import Foundation
import CadenceCore

/// Fills a training partner's plan from *their own* logged history, for the
/// owner's exercises only (field test 2026-08-18 #4). Mirrors the resolution
/// `SessionRenderModel` already performs at set-logging time, moved forward to
/// the plan editor so a partner's plan is reviewable *before* Start.
///
/// Pure by construction: the app assembles `ExerciseHistory` from
/// `WorkoutRepository` and hands it in, because `@Model` rows cannot cross into
/// a `Sendable` value layer safely.
public enum PartnerPlanResolver {

    /// One logged working set, canonical kg.
    public struct LoggedSet: Equatable, Sendable {
        public let weightKg: Double
        public let reps: Int

        public init(weightKg: Double, reps: Int) {
            self.weightKg = weightKg
            self.reps = reps
        }
    }

    /// One performer's history for ONE exercise, gathered by the caller from
    /// `WorkoutRepository`. All weights canonical kg.
    public struct ExerciseHistory: Equatable, Sendable {
        /// The most recent prior session's working sets, in logged order.
        public let lastSets: [LoggedSet]
        /// Working-set rep ladders for this exercise, oldest first.
        public let repLadders: [[Int]]
        /// The performer's first working weight for this exercise, if any.
        public let firstWorkingWeightKg: Double?
        /// The performer's rep pattern across ALL exercises, oldest first — used
        /// when they have never trained THIS movement.
        public let generalRepLadders: [[Int]]

        public init(lastSets: [LoggedSet] = [],
                    repLadders: [[Int]] = [],
                    firstWorkingWeightKg: Double? = nil,
                    generalRepLadders: [[Int]] = []) {
            self.lastSets = lastSets
            self.repLadders = repLadders
            self.firstWorkingWeightKg = firstWorkingWeightKg
            self.generalRepLadders = generalRepLadders
        }

        public static let empty = ExerciseHistory()
    }

    /// Resolve one performer's sets for one exercise.
    ///
    /// Order (decision **D13**):
    ///  1. history for THIS exercise → their ladder (index-wise, extended by
    ///     repeating the last logged set) + their own weight;
    ///  2. else their general rep pattern → those reps, weight nil;
    ///  3. else the owner's planned reps, weight nil.
    ///
    /// The result ALWAYS has `ownerSets.count` elements (decision **D12**), and a
    /// partner NEVER inherits the owner's weight.
    public static func sets(forOwnerSets ownerSets: [EditableSet],
                            history: ExerciseHistory) -> [EditableSet] {
        guard !ownerSets.isEmpty else { return [] }

        let logged = history.lastSets.filter { $0.reps > 0 }
        let ladder = logged.isEmpty ? (history.repLadders.last ?? []).filter { $0 > 0 } : []
        let general = (logged.isEmpty && ladder.isEmpty)
            ? (history.generalRepLadders.last ?? []).filter { $0 > 0 }
            : []

        return ownerSets.indices.map { index in
            if !logged.isEmpty {
                let set = logged[min(index, logged.count - 1)]
                let weight = set.weightKg > 0 ? set.weightKg : history.firstWorkingWeightKg
                return EditableSet(targetReps: set.reps, targetWeight: weight)
            }
            if !ladder.isEmpty {
                return EditableSet(targetReps: ladder[min(index, ladder.count - 1)],
                                   targetWeight: history.firstWorkingWeightKg)
            }
            if !general.isEmpty {
                return EditableSet(targetReps: general[min(index, general.count - 1)],
                                   targetWeight: nil)
            }
            return EditableSet(targetReps: ownerSets[index].targetReps, targetWeight: nil)
        }
    }

    /// The owner's own plan as a performer entry, so "Me" is always index 0.
    public static func ownerPlan(name: String = "Me",
                                 ownerSets: [EditableSet]) -> EditablePerformerPlan {
        EditablePerformerPlan(performerID: nil, name: name, sets: ownerSets)
    }

    /// One roster member: `performerID == nil` is the device owner.
    public struct RosterMember: Equatable, Sendable {
        public let performerID: UUID?
        public let name: String

        public init(performerID: UUID?, name: String) {
            self.performerID = performerID
            self.name = name
        }
    }

    /// Rebuild every exercise's `performerPlans` for the given roster.
    /// `history(exerciseName, performerID)` is supplied by the caller.
    ///
    /// A solo roster (owner only) clears `performerPlans` entirely, so removing
    /// the last partner leaves exactly the plan a solo user would have had.
    /// Idempotent: the owner's own `sets` are the source of truth for set count
    /// and are copied verbatim, never re-derived from history.
    public static func fill(plan: EditablePlan,
                            roster: [RosterMember],
                            history: (String, UUID?) -> ExerciseHistory) -> EditablePlan {
        var updated = plan
        let partners = roster.filter { $0.performerID != nil }
        guard !partners.isEmpty else {
            for index in updated.exercises.indices where !updated.exercises[index].performerPlans.isEmpty {
                updated.exercises[index].performerPlans = []
            }
            return updated
        }

        let ownerName = roster.first(where: { $0.performerID == nil })?.name ?? "Me"
        for index in updated.exercises.indices {
            let exercise = updated.exercises[index]
            let existing = exercise.performerPlans
            var plans = [reusingIdentity(
                of: existing.first { $0.performerID == nil },
                EditablePerformerPlan(performerID: nil, name: ownerName, sets: exercise.sets))]
            for partner in partners {
                let resolved = EditablePerformerPlan(
                    performerID: partner.performerID,
                    name: partner.name,
                    sets: sets(forOwnerSets: exercise.sets,
                               history: history(exercise.name, partner.performerID)))
                plans.append(reusingIdentity(
                    of: existing.first { $0.performerID == partner.performerID },
                    resolved))
            }
            updated.exercises[index].performerPlans = plans
        }
        return updated
    }

    /// Keeps every performer's plan the same shape as the owner's after the
    /// owner adds or removes a set (decision **D12**): the owner's entry mirrors
    /// `sets` exactly, and a partner's plan is extended by repeating their last
    /// planned set or truncated to the owner's count. No history is consulted —
    /// this is shape maintenance between full re-resolutions.
    public static func aligned(_ exercise: EditableExercise) -> EditableExercise {
        guard !exercise.performerPlans.isEmpty else { return exercise }
        var updated = exercise
        updated.performerPlans = exercise.performerPlans.map { plan in
            guard !plan.isMe else {
                return EditablePerformerPlan(id: plan.id, performerID: nil,
                                             name: plan.name, sets: exercise.sets)
            }
            guard plan.sets.count != exercise.sets.count else { return plan }
            var sets = Array(plan.sets.prefix(exercise.sets.count))
            while sets.count < exercise.sets.count {
                let last = sets.last ?? exercise.sets[sets.count]
                sets.append(EditableSet(targetReps: last.targetReps, targetWeight: last.targetWeight))
            }
            return EditablePerformerPlan(id: plan.id, performerID: plan.performerID,
                                         name: plan.name, sets: sets)
        }
        return updated
    }

    /// Re-resolving must not churn SwiftUI identity: when a performer's plan is
    /// already present, the rebuilt plan keeps that plan's `id` and its set ids
    /// positionally. Re-running `fill` on an unchanged roster therefore produces
    /// a value equal to the one it started from.
    private static func reusingIdentity(of existing: EditablePerformerPlan?,
                                        _ resolved: EditablePerformerPlan) -> EditablePerformerPlan {
        guard let existing else { return resolved }
        let sets = resolved.sets.enumerated().map { index, set -> EditableSet in
            guard index < existing.sets.count else { return set }
            return EditableSet(id: existing.sets[index].id,
                               targetReps: set.targetReps,
                               targetWeight: set.targetWeight)
        }
        return EditablePerformerPlan(id: existing.id,
                                     performerID: resolved.performerID,
                                     name: resolved.name,
                                     sets: sets)
    }
}
