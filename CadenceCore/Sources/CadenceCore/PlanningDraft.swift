import Foundation
import SwiftData

/// A durable, user-owned, unscheduled workout draft. The model owns only
/// metadata plus an opaque versioned payload; `PlanningDraftPayload` owns the
/// full editable plan. Deliberately separate from `ScheduledWorkout`, which is
/// execution scheduling state.
@Model
public final class PlanningDraft {
    public var id: UUID = UUID()
    public var title: String = "Workout"
    public var payloadData: Data = Data()
    public var payloadVersion: Int = PlanningDraftPayload.currentVersion
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var originDevice: String = ""
    public var deletedAt: Date?

    public init(id: UUID = UUID(), title: String = "Workout",
                payloadData: Data, payloadVersion: Int = PlanningDraftPayload.currentVersion,
                createdAt: Date = Date(), updatedAt: Date = Date(),
                originDevice: String = "") {
        self.id = id
        self.title = title
        self.payloadData = payloadData
        self.payloadVersion = payloadVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originDevice = originDevice
    }

    public var isVisible: Bool { deletedAt == nil }

    /// The most recently updated visible draft, or nil. Never mutates rows.
    public static func current(in context: ModelContext) throws -> PlanningDraft? {
        try context.fetch(FetchDescriptor<PlanningDraft>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])).first
    }
}

public struct PlanningDraftPayload: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var plan: EditablePlanPayload

    public init(plan: EditablePlanPayload) { self.plan = plan }
}

/// Explicit, lossless DTO for the editor's plan. Mirrors `EditablePlan` in
/// `CadenceFeatures` (which converts to and from it) without SwiftData or the
/// editor value type encoding anything implicitly.
public struct EditablePlanPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var warmupMinutes: Int
    public var cooldownMinutes: Int
    public var exercises: [EditableExercisePayload]
    public var partnerIDs: [UUID]
    public var enginePlanId: String?
    public var engineRevisionId: String?
    public var enginePlanJSON: Data?
    public var suggestedWorkoutStyleRaw: String?
    public var recommendationRationale: RationalePayload?

    public init(id: UUID, title: String, warmupMinutes: Int, cooldownMinutes: Int,
                exercises: [EditableExercisePayload], partnerIDs: [UUID],
                enginePlanId: String? = nil, engineRevisionId: String? = nil,
                enginePlanJSON: Data? = nil, suggestedWorkoutStyleRaw: String? = nil,
                recommendationRationale: RationalePayload? = nil) {
        self.id = id
        self.title = title
        self.warmupMinutes = warmupMinutes
        self.cooldownMinutes = cooldownMinutes
        self.exercises = exercises
        self.partnerIDs = partnerIDs
        self.enginePlanId = enginePlanId
        self.engineRevisionId = engineRevisionId
        self.enginePlanJSON = enginePlanJSON
        self.suggestedWorkoutStyleRaw = suggestedWorkoutStyleRaw
        self.recommendationRationale = recommendationRationale
    }
}

public struct EditableExercisePayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var supersetGroupRaw: String?
    public var sets: [EditableSetPayload]
    public var performerPlans: [EditablePerformerPlanPayload]

    public init(id: UUID, name: String, notes: String, supersetGroupRaw: String?,
                sets: [EditableSetPayload], performerPlans: [EditablePerformerPlanPayload]) {
        self.id = id
        self.name = name
        self.notes = notes
        self.supersetGroupRaw = supersetGroupRaw
        self.sets = sets
        self.performerPlans = performerPlans
    }
}

public struct EditablePerformerPlanPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var performerID: UUID?
    public var name: String
    public var sets: [EditableSetPayload]

    public init(id: UUID, performerID: UUID?, name: String, sets: [EditableSetPayload]) {
        self.id = id
        self.performerID = performerID
        self.name = name
        self.sets = sets
    }
}

public struct EditableSetPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var targetReps: Int
    public var targetWeight: Double?
    public var loadModeRaw: String
    public var oneRepMaxPercent: Double?

    public init(id: UUID, targetReps: Int, targetWeight: Double?,
                loadModeRaw: String, oneRepMaxPercent: Double?) {
        self.id = id
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.loadModeRaw = loadModeRaw
        self.oneRepMaxPercent = oneRepMaxPercent
    }
}

public struct RationalePayload: Codable, Equatable, Sendable {
    public struct Exercise: Codable, Equatable, Sendable {
        public var exerciseName: String
        public var whyExercise: String
        public var whySetRep: String

        public init(exerciseName: String, whyExercise: String, whySetRep: String) {
            self.exerciseName = exerciseName
            self.whyExercise = whyExercise
            self.whySetRep = whySetRep
        }
    }

    public var whyWorkout: String
    public var exercises: [Exercise]

    public init(whyWorkout: String, exercises: [Exercise]) {
        self.whyWorkout = whyWorkout
        self.exercises = exercises
    }
}

public enum PlanningDraftCodecError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
}
