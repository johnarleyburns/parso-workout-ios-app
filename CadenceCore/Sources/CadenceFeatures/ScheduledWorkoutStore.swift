import Foundation
import SwiftData
import CadenceCore

/// Codable value snapshot used by the one-off schedule feature. The snapshot is
/// intentionally independent of the mutable editor and of any future coach
/// regeneration.
public struct ScheduledWorkoutPayload: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public enum Source: String, Codable, Sendable {
        case custom
        case personalized
        case previousWorkout
        case routine
    }

    public struct Performer: Codable, Equatable, Sendable {
        public var performerID: UUID?
        public var name: String
        public var sets: [Set]

        public init(performerID: UUID?, name: String, sets: [Set]) {
            self.performerID = performerID
            self.name = name
            self.sets = sets
        }
    }

    public struct Set: Codable, Equatable, Sendable {
        public var targetReps: Int
        public var targetWeight: Double?
        public var loadMode: String
        public var oneRepMaxPercent: Double?

        public init(targetReps: Int, targetWeight: Double?, loadMode: String,
                    oneRepMaxPercent: Double?) {
            self.targetReps = targetReps
            self.targetWeight = targetWeight
            self.loadMode = loadMode
            self.oneRepMaxPercent = oneRepMaxPercent
        }
    }

    public struct Exercise: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var notes: String
        public var sets: [Set]
        public var performerPlans: [Performer]

        public init(id: UUID, name: String, notes: String, sets: [Set],
                    performerPlans: [Performer]) {
            self.id = id
            self.name = name
            self.notes = notes
            self.sets = sets
            self.performerPlans = performerPlans
        }
    }

    public var title: String
    public var warmupMinutes: Int
    public var cooldownMinutes: Int
    public var exercises: [Exercise]
    public var partnerIDs: [UUID]
    public var source: Source
    /// Retains the exact suggestion boundary so a scheduled Personalized
    /// workout keeps its selected style when it is started or rescheduled.
    /// Optional for payloads written before this field existed.
    public var suggestedWorkoutStyleRaw: String?

    public init(title: String, warmupMinutes: Int, cooldownMinutes: Int,
                exercises: [Exercise], partnerIDs: [UUID], source: Source,
                suggestedWorkoutStyleRaw: String? = nil) {
        self.title = title
        self.warmupMinutes = warmupMinutes
        self.cooldownMinutes = cooldownMinutes
        self.exercises = exercises
        self.partnerIDs = partnerIDs
        self.source = source
        self.suggestedWorkoutStyleRaw = suggestedWorkoutStyleRaw
    }

    public init(plan: EditablePlan) {
        let source: Source
        if plan.suggestedWorkoutStyle != nil {
            source = .personalized
        } else if plan.title.localizedCaseInsensitiveContains("previous") {
            source = .previousWorkout
        } else {
            source = .custom
        }
        self.init(
            title: plan.title,
            warmupMinutes: plan.warmupMinutes,
            cooldownMinutes: plan.cooldownMinutes,
            exercises: plan.exercises.map { exercise in
                Exercise(
                    id: exercise.id,
                    name: exercise.name,
                    notes: exercise.notes,
                    sets: exercise.sets.map { set in
                        Set(targetReps: set.targetReps,
                            targetWeight: set.targetWeight,
                            loadMode: set.loadMode.rawValue,
                            oneRepMaxPercent: set.oneRepMaxPercent)
                    },
                    performerPlans: exercise.performerPlans.map { performer in
                        Performer(
                            performerID: performer.performerID,
                            name: performer.name,
                            sets: performer.sets.map { set in
                                Set(targetReps: set.targetReps,
                                    targetWeight: set.targetWeight,
                                    loadMode: set.loadMode.rawValue,
                                    oneRepMaxPercent: set.oneRepMaxPercent)
                            })
                    })
            },
            partnerIDs: plan.partnerIDs,
            source: source,
            suggestedWorkoutStyleRaw: plan.suggestedWorkoutStyle?.rawValue)
    }

    public func editablePlan() -> EditablePlan {
        EditablePlan(
            title: title,
            warmupMinutes: warmupMinutes,
            cooldownMinutes: cooldownMinutes,
            exercises: exercises.map { exercise in
                EditableExercise(
                    name: exercise.name,
                    sets: exercise.sets.map(Self.editableSet),
                    notes: exercise.notes,
                    performerPlans: exercise.performerPlans.map { performer in
                        EditablePerformerPlan(
                            performerID: performer.performerID,
                            name: performer.name,
                            sets: performer.sets.map(Self.editableSet))
                    })
            },
            partnerIDs: partnerIDs,
            suggestedWorkoutStyle: suggestedWorkoutStyleRaw
                .flatMap(SuggestedWorkoutStyle.init(rawValue:))
                ?? (source == .personalized ? .fitness : nil))
    }

    private static func editableSet(_ set: Set) -> EditableSet {
        EditableSet(
            targetReps: set.targetReps,
            targetWeight: set.targetWeight,
            loadMode: EditableLoadMode(rawValue: set.loadMode) ?? .straight,
            oneRepMaxPercent: set.oneRepMaxPercent)
    }
}

public enum ScheduledWorkoutStore {
    public static let currentPayloadVersion = ScheduledWorkoutPayload.currentVersion

    public static func encode(_ plan: EditablePlan) throws -> Data {
        try JSONEncoder().encode(ScheduledWorkoutPayload(plan: plan))
    }

    public static func decode(_ data: Data, version: Int) throws -> EditablePlan {
        guard version == currentPayloadVersion else {
            throw ScheduledWorkoutStoreError.unsupportedPayloadVersion(version)
        }
        return try JSONDecoder().decode(ScheduledWorkoutPayload.self, from: data).editablePlan()
    }

    @discardableResult
    public static func schedule(plan: EditablePlan, for date: Date,
                                calendar: Calendar = .current,
                                originDevice: String = "iphone",
                                in context: ModelContext) throws -> ScheduledWorkout {
        let normalized = ScheduledWorkoutDate.normalize(date, calendar: calendar)
        let record = ScheduledWorkout(
            scheduledDate: normalized,
            scheduledDayKey: ScheduledWorkoutDate.dayKey(normalized, calendar: calendar),
            timeZoneIdentifier: calendar.timeZone.identifier,
            title: plan.title.isEmpty ? "Workout" : plan.title,
            payloadData: try encode(plan),
            payloadVersion: currentPayloadVersion,
            originDevice: originDevice)
        context.insert(record)
        try context.save()
        return record
    }

    public static func active(in context: ModelContext) throws -> [ScheduledWorkout] {
        try context.fetch(FetchDescriptor<ScheduledWorkout>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\ScheduledWorkout.scheduledDate),
                     SortDescriptor(\ScheduledWorkout.title)]))
            .filter { $0.status != .cancelled && $0.status != .completed }
    }

    @discardableResult
    public static func markStarted(recordID: UUID, sessionID: UUID,
                                   in context: ModelContext) throws -> Bool {
        guard let record = try record(recordID, in: context), record.isVisible else { return false }
        record.status = .started
        record.startedSessionID = sessionID
        record.updatedAt = Date()
        try context.save()
        return true
    }

    @discardableResult
    public static func markCompleted(recordID: UUID, in context: ModelContext) throws -> Bool {
        guard let record = try record(recordID, in: context), record.isVisible else { return false }
        record.status = .completed
        record.updatedAt = Date()
        try context.save()
        return true
    }

    /// Returns a started schedule to the actionable queue when its linked
    /// session was abandoned before completion. Completed/cancelled items are
    /// never resurrected.
    @discardableResult
    public static func markAbandoned(recordID: UUID, in context: ModelContext) throws -> Bool {
        guard let record = try record(recordID, in: context),
              record.status == .started, record.deletedAt == nil else { return false }
        record.status = .scheduled
        record.startedSessionID = nil
        record.updatedAt = Date()
        try context.save()
        return true
    }

    @discardableResult
    public static func cancel(recordID: UUID, in context: ModelContext) throws -> Bool {
        guard let record = try record(recordID, in: context), record.deletedAt == nil else { return false }
        record.status = .cancelled
        record.deletedAt = Date()
        record.updatedAt = Date()
        try context.save()
        return true
    }

    private static func record(_ id: UUID, in context: ModelContext) throws -> ScheduledWorkout? {
        try context.fetch(FetchDescriptor<ScheduledWorkout>(
            predicate: #Predicate { $0.id == id })).first
    }
}

public enum ScheduledWorkoutStoreError: Error, Equatable, Sendable {
    case unsupportedPayloadVersion(Int)
}
