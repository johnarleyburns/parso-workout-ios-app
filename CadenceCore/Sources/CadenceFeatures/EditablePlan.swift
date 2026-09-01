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
    /// Optional DB++ provenance carried from a generated plan into the
    /// materialised WorkoutSession. Nil keeps legacy/user-created drafts intact.
    public var enginePlanId: String?
    public var engineRevisionId: String?
    public var enginePlanJSON: Data?

    public init(title: String = "Workout", warmupMinutes: Int, cooldownMinutes: Int,
                exercises: [EditableExercise], partnerIDs: [UUID] = [],
                enginePlanId: String? = nil, engineRevisionId: String? = nil,
                enginePlanJSON: Data? = nil) {
        self.title = title
        self.warmupMinutes = warmupMinutes
        self.cooldownMinutes = cooldownMinutes
        self.exercises = exercises
        self.partnerIDs = partnerIDs
        self.enginePlanId = enginePlanId
        self.engineRevisionId = engineRevisionId
        self.enginePlanJSON = enginePlanJSON
    }

    public static func empty(warmup: Int, cooldown: Int) -> EditablePlan {
        EditablePlan(warmupMinutes: warmup, cooldownMinutes: cooldown, exercises: [])
    }

    public static func from(session: WorkoutSession) -> EditablePlan {
        let performerNames = Dictionary(
            session.orderedSets.compactMap { set -> (String, String)? in
                guard let person = set.performedBy, !person.isMe else { return nil }
                return (person.id.uuidString, person.name)
            },
            uniquingKeysWith: { first, _ in first })
        let storedPlans = session.plannedPerformerPrescriptions
        let exercises = session.exercisesInOrder.map { ex -> EditableExercise in
            let sets = session.orderedSets.filter { $0.exercise?.id == ex.id && $0.isOwnerSet }
            return EditableExercise(
                name: ex.name,
                sets: sets.map { EditableSet(targetReps: $0.reps, targetWeight: $0.weight > 0 ? $0.weight : nil) },
                notes: "",
                performerPlans: performerPlans(forExerciseNamed: ex.name,
                                               stored: storedPlans,
                                               names: performerNames)
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

    /// Rebuilds one exercise's per-performer plans from a session's stored
    /// prescriptions, so "start from a previous workout" keeps partner plans.
    private static func performerPlans(forExerciseNamed name: String,
                                       stored: [PlannedPerformerPrescription],
                                       names: [String: String]) -> [EditablePerformerPlan] {
        guard !stored.isEmpty else { return [] }
        return stored.compactMap { performer -> EditablePerformerPlan? in
            guard let prescription = performer.exercises.first(where: {
                $0.exerciseName.caseInsensitiveCompare(name) == .orderedSame
            }) else { return nil }
            let id = performer.performerID.flatMap(UUID.init(uuidString:))
            return EditablePerformerPlan(
                performerID: id,
                name: id == nil ? "Me" : (names[performer.performerID ?? ""] ?? "Partner"),
                sets: prescription.sets.map { EditableSet(targetReps: $0.targetReps,
                                                          targetWeight: $0.targetWeightKg,
                                                          loadMode: EditableLoadMode(rawValue: $0.targetLoadMode ?? "straight") ?? .straight,
                                                          oneRepMaxPercent: $0.oneRepMaxPercent) })
        }
    }

    /// Applies the draft's complete prescription to a live session. Keeping
    /// this operation here prevents Home and Planning from silently reducing
    /// a multi-exercise plan to the first exercise's ladder.
    public func apply(to session: WorkoutSession) {
        session.enginePlanId = enginePlanId
        session.engineRevisionId = engineRevisionId
        session.enginePlanJSON = enginePlanJSON
        session.plannedExerciseNames = exercises.map(\.name)
        session.plannedPrescriptions = exercises.map { exercise in
            PlannedExercisePrescription(
                exerciseName: exercise.name,
                sets: exercise.sets.map { PlannedSetPrescription(
                    targetReps: $0.targetReps,
                    targetWeightKg: $0.targetWeight,
                    targetLoadMode: $0.loadMode == .straight ? nil : $0.loadMode.rawValue,
                    oneRepMaxPercent: $0.oneRepMaxPercent) })
        }
        session.plannedRepLadder = exercises.first?.sets.map(\.targetReps) ?? []
        let firstWeights = exercises.compactMap { $0.sets.first?.targetWeight }
        session.prescribedLoadKg = firstWeights.first ?? 0
        session.activePartnerIDs = partnerIDs.map(\.uuidString)
        session.plannedPerformerPrescriptions = performerPrescriptions()
        let rirNotes = exercises.compactMap { ex -> String? in
            guard !ex.notes.isEmpty, ex.notes.contains("RIR") else { return nil }
            return ex.notes
        }
        session.notes = rirNotes.isEmpty ? nil : rirNotes.joined(separator: "; ")
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
    public static func strengthAnyway(facts: CoachFacts,
                                      desiredSetsPerExercise: Int = 3) -> EditablePlan? {
        let exercises = CoachSession.fullBodyStrengthExercises(
            facts: facts,
            desiredSetsPerExercise: desiredSetsPerExercise
        )
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

    /// Every performer's prescription, grouped by performer in roster order
    /// (decision **D11**). The owner is **included** so the stored plan and
    /// `plannedPrescriptions` resolve through one code path; empty when the plan
    /// is solo, which leaves the session's field empty exactly as before.
    public func performerPrescriptions() -> [PlannedPerformerPrescription] {
        var order: [UUID?] = []
        var byPerformer: [String: [PlannedExercisePrescription]] = [:]
        for exercise in exercises {
            for plan in exercise.performerPlans {
                let key = plan.performerID?.uuidString ?? ""
                if byPerformer[key] == nil {
                    byPerformer[key] = []
                    order.append(plan.performerID)
                }
                byPerformer[key]?.append(PlannedExercisePrescription(
                    exerciseName: exercise.name,
                    sets: plan.sets.map { PlannedSetPrescription(targetReps: $0.targetReps,
                                                                 targetWeightKg: $0.targetWeight,
                                                                 targetLoadMode: $0.loadMode == .straight ? nil : $0.loadMode.rawValue,
                                                                 oneRepMaxPercent: $0.oneRepMaxPercent) }))
            }
        }
        return order.map { performerID in
            PlannedPerformerPrescription(performerID: performerID?.uuidString,
                                         exercises: byPerformer[performerID?.uuidString ?? ""] ?? [])
        }
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
    /// Per-performer plans, "Me" first (field test 2026-08-18 #4). Empty means a
    /// solo workout; `sets` remains the owner's plan and the source of truth for
    /// set COUNT for every performer (decision **D12**).
    public var performerPlans: [EditablePerformerPlan] = []

    public init(name: String, sets: [EditableSet], notes: String,
                performerPlans: [EditablePerformerPlan] = []) {
        self.name = name
        self.sets = sets
        self.notes = notes
        self.performerPlans = performerPlans
    }
}

/// One performer's set plan inside an editable exercise. `performerID == nil`
/// is the owner ("Me"), always first.
public struct EditablePerformerPlan: Identifiable, Hashable {
    public let id: UUID
    public var performerID: UUID?
    public var name: String
    public var sets: [EditableSet]

    public var isMe: Bool { performerID == nil }

    public init(id: UUID = UUID(), performerID: UUID?, name: String, sets: [EditableSet]) {
        self.id = id
        self.performerID = performerID
        self.name = name
        self.sets = sets
    }
}

public struct EditableSet: Identifiable, Hashable {
    public let id: UUID
    public var targetReps: Int
    public var targetWeight: Double?
    public var loadMode: EditableLoadMode
    public var oneRepMaxPercent: Double?

    /// `id` is settable so a re-resolved partner plan can keep the row identity
    /// SwiftUI already has (`PartnerPlanResolver.fill`), instead of rebuilding
    /// every row on each roster change.
    public init(id: UUID = UUID(), targetReps: Int, targetWeight: Double?,
                loadMode: EditableLoadMode = .straight,
                oneRepMaxPercent: Double? = nil) {
        self.id = id
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.loadMode = loadMode
        self.oneRepMaxPercent = oneRepMaxPercent
    }
}

/// How a planned set's load should be interpreted before it is started.
public enum EditableLoadMode: String, CaseIterable, Hashable, Sendable {
    case straight
    case percentageOfOneRepMax
    case bodyweight
}
