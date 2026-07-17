import Foundation
import CadenceCore

/// The editable workout draft the plan editor renders and hands back on Start.
/// Moved out of `Features/Home/WorkoutPlanEditor.swift` (test-pyramid Phase 3);
/// the four `from(...)` mappers are pure and were ideal unit-test material. The
/// SwiftUI editor view stays in the app.
public struct EditablePlan: Hashable {
    public let id = UUID()
    public var title: String = "Workout"
    public var warmupMinutes: Int
    public var cooldownMinutes: Int
    public var exercises: [EditableExercise]
    public var partnerIDs: [UUID] = []

    public init(title: String = "Workout", warmupMinutes: Int, cooldownMinutes: Int,
                exercises: [EditableExercise], partnerIDs: [UUID] = []) {
        self.title = title
        self.warmupMinutes = warmupMinutes
        self.cooldownMinutes = cooldownMinutes
        self.exercises = exercises
        self.partnerIDs = partnerIDs
    }

    public static func empty(warmup: Int, cooldown: Int) -> EditablePlan {
        EditablePlan(warmupMinutes: warmup, cooldownMinutes: cooldown, exercises: [])
    }

    public static func from(session: WorkoutSession) -> EditablePlan {
        let exercises = session.exercisesInOrder.map { ex -> EditableExercise in
            let sets = session.orderedSets.filter { $0.exercise?.id == ex.id && $0.isOwnerSet }
            return EditableExercise(
                name: ex.name,
                sets: sets.map { EditableSet(targetReps: $0.reps, targetWeight: $0.weight > 0 ? $0.weight : nil) },
                notes: ""
            )
        }
        return EditablePlan(
            title: session.title,
            warmupMinutes: 0,
            cooldownMinutes: 0,
            exercises: exercises,
            partnerIDs: session.activePartnerIDs.compactMap(UUID.init(uuidString:))
        )
    }

    public static func from(plan: WorkoutPlan, ladder: [Int]?, unit: MeasurementUnitPreference,
                            warmupMinutes: Int = 0, cooldownMinutes: Int = 0) -> EditablePlan {
        let reps = ladder ?? []
        let exercises = plan.items.map { item -> EditableExercise in
            let setsCount = max(item.targetSets ?? reps.count, reps.isEmpty ? 3 : reps.count)
            let sets = (0..<setsCount).map { i -> EditableSet in
                let r = i < reps.count ? reps[i] : (item.reps ?? 5)
                return EditableSet(targetReps: r, targetWeight: nil)
            }
            return EditableExercise(name: item.movement, sets: sets, notes: item.note ?? "")
        }
        return EditablePlan(
            title: plan.name,
            warmupMinutes: warmupMinutes,
            cooldownMinutes: cooldownMinutes,
            exercises: exercises
        )
    }

    public static func from(recommendation: Recommendation,
                            goal: TrainingGoal = .hypertrophy,
                            warmupMinutes: Int = 0, cooldownMinutes: Int = 0) -> EditablePlan {
        let prescribed = recommendation.prescribedSession(goal: goal)
        let ladder = prescribed.repLadder
        let names = prescribed.exerciseNames
        let exercises = names.map { name -> EditableExercise in
            let sets = ladder.isEmpty
                ? [EditableSet(targetReps: 5, targetWeight: prescribed.loadKg)]
                : ladder.map { EditableSet(targetReps: $0, targetWeight: prescribed.loadKg) }
            return EditableExercise(name: name, sets: sets, notes: "")
        }
        return EditablePlan(
            title: prescribed.title,
            warmupMinutes: warmupMinutes,
            cooldownMinutes: cooldownMinutes,
            exercises: exercises
        )
    }

    public static func from(coach session: CoachSession) -> EditablePlan? {
        guard let exercises = session.exercises, !exercises.isEmpty else { return nil }
        return EditablePlan(
            title: session.title,
            warmupMinutes: 5,
            cooldownMinutes: 0,
            exercises: exercises.map { ex in
                let setCount = ex.sets ?? 3
                let ladder = ex.repLadder ?? []
                return EditableExercise(
                    name: ex.name,
                    sets: (0..<setCount).map { i in
                        EditableSet(
                            targetReps: i < ladder.count ? ladder[i] : (ex.repsLow ?? 8),
                            targetWeight: ex.loadKg
                        )
                    },
                    notes: ex.rir.map { "Target ≤\($0) RIR" } ?? ""
                )
            },
            partnerIDs: []
        )
    }

    /// "Do a strength workout anyway" (coach-user-control Phase 5): when today's
    /// coach plan carries no strength, the user can still ask for one. Builds the
    /// best-fit full-body session from the user's own trained movements and goal
    /// rep scheme — a suggestion for perusal in the plan editor, never a launch.
    public static func strengthAnyway(facts: CoachFacts) -> EditablePlan? {
        let exercises = CoachSession.fullBodyStrengthExercises(facts: facts)
        guard !exercises.isEmpty else { return nil }
        let range = facts.goal.repRange
        let rir = facts.goal.targetRIR
        return from(coach: CoachSession(
            id: "strength.userAnyway",
            kind: .strength,
            title: "Strength session",
            subtitle: "\(range.lowerBound)–\(range.upperBound) reps · ≤\(rir) RIR",
            durationMinutes: 45,
            exercises: exercises,
            trainingLoadTags: ["strength"],
            citationIds: ["schoenfeld2021"],
            launchPayload: .strengthPlan("fullBody")))
    }

    /// De-dupes partner ids and drops an owner-only list to empty (solo). Pure
    /// version of the editor's roster normalization.
    public static func normalizedPartnerIDs(_ ids: [UUID], ownerID: UUID?) -> [UUID] {
        var seen = Set<UUID>()
        let cleaned = ids.filter { seen.insert($0).inserted }
        return cleaned.contains(where: { $0 != ownerID }) ? cleaned : []
    }
}

public struct EditableExercise: Identifiable, Hashable {
    public let id = UUID()
    public var name: String
    public var sets: [EditableSet]
    public var notes: String

    public init(name: String, sets: [EditableSet], notes: String) {
        self.name = name
        self.sets = sets
        self.notes = notes
    }
}

public struct EditableSet: Identifiable, Hashable {
    public let id = UUID()
    public var targetReps: Int
    public var targetWeight: Double?

    public init(targetReps: Int, targetWeight: Double?) {
        self.targetReps = targetReps
        self.targetWeight = targetWeight
    }
}
