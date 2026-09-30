import Foundation
import SwiftData

// MARK: - JSON v8 native-store archive

/// A deliberately explicit registry for the native SwiftData archive. Keeping
/// the entity names in one place makes adding a model a compile-time review
/// point and gives the coverage test a stable ratchet.
public struct ExportNativeDatabase: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let entityNames: [String] = [
        "WorkoutSession", "Exercise", "SetEntry", "SessionTemplate",
        "TemplateExercise", "CardioWorkout", "ReadinessEntry", "HRSample",
        "RouteSample", "HRMDevice", "Person", "Assessment", "PersistedPlan",
        "PersistedPlanHeader", "PersistedPlanWeek", "PersistedPlanDay",
        "PersistedPlanSession", "PersistedPlanItem", "PersistedPlanSet",
        "PersistedClientRelationship", "ExerciseSuggestionExclusion",
        "ScheduledWorkout"
    ]

    public var schemaVersion: Int
    public var records: [ExportNativeRecord]

    public init(schemaVersion: Int = ExportNativeDatabase.schemaVersion,
                records: [ExportNativeRecord] = []) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    public var entityNamesPresent: Set<String> {
        Set(records.map(\.entity))
    }
}

public struct ExportNativeRecord: Codable, Equatable, Sendable {
    public var entity: String
    public var id: UUID
    public var updatedAt: Date?
    /// JSON for the row is nested as Data so the outer export remains stable
    /// when a model gains an additive field. JSONEncoder represents Data as
    /// base64; this is lossless and keeps the archive language-independent.
    public var payload: Data

    public init(entity: String, id: UUID, updatedAt: Date?, payload: Data) {
        self.entity = entity
        self.id = id
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

private struct NativeWorkoutSession: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var date: Date
    var endedAt: Date?
    var plannedExerciseNames: [String]
    var plannedRepLadder: [Int]
    var plannedPrescriptions: [PlannedExercisePrescription]
    var plannedPerformerPrescriptions: [PlannedPerformerPrescription]
    var notes: String?
    var templateName: String?
    var planKey: String?
    var enginePlanId: String?
    var engineRevisionId: String?
    var enginePlanJSON: Data?
    var planSessionID: UUID?
    var scheduledWorkoutID: UUID?
    var healthKitWorkoutUUID: UUID?
    var isLogged: Bool
    var deletedAt: Date?
    var warmupSeconds: Double
    var cooldownSeconds: Double
    var prescribedLoadKg: Double
    var activePartnerIDs: [String]
    var updatedAt: Date
    var originDevice: String
    var setIDs: [UUID]
}

private struct NativeSetEntry: Codable, Equatable, Sendable {
    var id: UUID
    var weight: Double
    var reps: Int
    var order: Int
    var isWarmup: Bool
    var usesBodyweight: Bool
    var rpe: Double?
    var note: String?
    var completedAt: Date
    var updatedAt: Date
    var originDevice: String
    var barWeightKg: Double
    var loadMultiplier: Double
    var loadAccountingMode: String?
    var sessionID: UUID?
    var exerciseID: UUID?
    var performerID: UUID?
}

private struct NativeExercise: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var category: String?
    var muscleGroups: [String]
    var isCustom: Bool
    var equipment: String?
    var isLateral: Bool
    var mechanics: String?
    var force: String?
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var searchKeywords: [String]
    var instructions: [String]
    var imageName: String?
    var level: String?
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var originDevice: String
    var loadAccountingMode: String?
    var defaultBarWeightKg: Double
    var loadAccountingUserOverride: Bool
    var directMuscles: [String]
    var indirectMuscles: [String]
    var stabilizerMuscles: [String]
    var trainingTypes: [String]
    var modalities: [String]
    var sportContexts: [String]
    var movementPatternIDs: [String]
    var volumeEligible: Bool
    var annotationConfidence: String?
    var sourceExerciseID: String?
}

private struct NativePerson: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var isMe: Bool
    var createdAt: Date
    var updatedAt: Date
    var originDevice: String
}

private struct NativeTemplate: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var originDevice: String
    var exerciseIDs: [UUID]
}

private struct NativeTemplateExercise: Codable, Equatable, Sendable {
    var id: UUID
    var exerciseName: String
    var order: Int
    var targetSets: Int
    var targetReps: Int
    var templateID: UUID?
}

private struct NativeCardio: Codable, Equatable, Sendable {
    var id: UUID
    var type: String
    var start: Date
    var end: Date?
    var distance: Double?
    var activeEnergy: Double?
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var laps: Int?
    var targetLaps: Int?
    var targetDistance: Double?
    var source: String
    var healthKitWorkoutUUID: UUID?
    var notes: String?
    var isLogged: Bool
    var deletedAt: Date?
    var customTitle: String?
    var importedWorkoutKindRaw: String?
    var intervalDetailData: String
    var cardioAlgorithmVersionRaw: String?
    var effectiveRestingHR: Double?
    var effectiveMaximumHR: Double?
    var heartRateMaximumSourceRaw: String?
    var trainingZonePolicyRaw: String?
    var intensitySummaryData: String
    var intensityProfileData: String
    var standardMETMinutes: Double?
    var standardMETValue: Double?
    var metBasisRaw: String?
    var metMethodRaw: String?
    var updatedAt: Date
    var originDevice: String
}

private struct NativeHRSample: Codable, Equatable, Sendable {
    var id: UUID
    var t: TimeInterval
    var bpm: Double
    var cardioID: UUID?
}

private struct NativeRouteSample: Codable, Equatable, Sendable {
    var id: UUID
    var t: TimeInterval
    var lat: Double
    var lon: Double
    var elevation: Double
    var cardioID: UUID?
}

private struct NativeReadiness: Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var muscleSoreness: Int
    var fatigueEnergy: Int
    var sleepQuality: Int
    var stressMood: Int
    var hasPainOrIllnessConcern: Bool
    var updatedAt: Date
}

private struct NativeHRMDevice: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var lastBattery: Int?
    var isDefault: Bool
    var lastConnectedAt: Date?
    var updatedAt: Date
}

private struct NativeAssessment: Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var kind: String
    var value: Double
    var inputWeight: Double
    var inputReps: Int
    var exerciseName: String?
    var protocolName: String?
    var notes: String?
    var updatedAt: Date
    var originDevice: String
    var inputDistance: Double?
    var inputTime: Double?
    var inputEndingHR: Double?
    var inputAge: Int?
    var inputSex: Int?
}

private struct NativePersistedPlan: Codable, Equatable, Sendable {
    var id: UUID
    var payloadVersion: Int
    var planData: Data
    var updatedAt: Date
    var originDevice: String
    var deletedAt: Date?
}

private struct NativePlanHeader: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var provenanceData: Data
    var goalRaw: String
    var horizonData: Data
    var createdAt: Date
    var updatedAt: Date
    var authoredOnIdiomRaw: String?
    var statusRaw: String
    var notes: String?
    var rationaleData: Data?
    var originDevice: String
}

private struct NativePlanWeek: Codable, Equatable, Sendable {
    var id: UUID
    var planID: UUID
    var index: Int
    var intendedProgressionRaw: String?
    var isDeload: Bool
}

private struct NativePlanDay: Codable, Equatable, Sendable {
    var id: UUID
    var weekID: UUID
    var weekdayRaw: Int
}

private struct NativePlanSession: Codable, Equatable, Sendable {
    var id: UUID
    var dayID: UUID
    var title: String
    var goalRaw: String
    var estimatedDurationMinutes: Int?
    var statusRaw: String
    var startedAt: Date?
    var completedAt: Date?
    var sessionRPE: Double?
    var painData: Data?
    var note: String?
    var partnersData: Data
}

private struct NativePlanItem: Codable, Equatable, Sendable {
    var id: UUID
    var sessionID: UUID
    var kindRaw: String
    var order: Int
    var payloadData: Data
}

private struct NativePlanSet: Codable, Equatable, Sendable {
    var id: UUID
    var itemID: UUID
    var setIndex: Int
    var payloadData: Data
}

private struct NativeClientRelationship: Codable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var notes: String?
    var goalRaw: String?
    var statusRaw: String
    var shareZoneID: UUID?
    var shareURLString: String?
    var createdAt: Date
    var updatedAt: Date
}

private struct NativeSuggestionExclusion: Codable, Equatable, Sendable {
    var id: UUID
    var exerciseKey: String
    var exerciseNameSnapshot: String
    var reasonRaw: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var originDevice: String
}

private struct NativeScheduledWorkout: Codable, Equatable, Sendable {
    var id: UUID
    var scheduledDate: Date
    var scheduledDayKey: String
    var timeZoneIdentifier: String
    var title: String
    var payloadData: Data
    var payloadVersion: Int
    var statusRaw: String
    var startedSessionID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var originDevice: String
}

private enum NativeArchiveCodec {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) throws -> Data { try encoder.encode(value) }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

public enum NativeDatabaseExport {
    public static func build(from context: ModelContext) throws -> ExportNativeDatabase {
        var records: [ExportNativeRecord] = []

        func append<T: Encodable>(_ entity: String, id: UUID, updatedAt: Date?, _ value: T) throws {
            records.append(ExportNativeRecord(entity: entity, id: id, updatedAt: updatedAt,
                                               payload: try NativeArchiveCodec.encode(value)))
        }

        for row in try context.fetch(FetchDescriptor<WorkoutSession>()) {
            try append("WorkoutSession", id: row.id, updatedAt: row.updatedAt,
                        NativeWorkoutSession(id: row.id, title: row.title, date: row.date,
                                             endedAt: row.endedAt,
                                             plannedExerciseNames: row.plannedExerciseNames,
                                             plannedRepLadder: row.plannedRepLadder,
                                             plannedPrescriptions: row.plannedPrescriptions,
                                             plannedPerformerPrescriptions: row.plannedPerformerPrescriptions.map {
                                                 PlannedPerformerPrescription(performerID: $0.performerID,
                                                                                exercises: $0.exercises)
                                             },
                                             notes: row.notes, templateName: row.templateName,
                                             planKey: row.planKey, enginePlanId: row.enginePlanId,
                                             engineRevisionId: row.engineRevisionId,
                                             enginePlanJSON: row.enginePlanJSON,
                                             planSessionID: row.planSessionID,
                                             scheduledWorkoutID: row.scheduledWorkoutID,
                                             healthKitWorkoutUUID: row.healthKitWorkoutUUID,
                                             isLogged: row.isLogged, deletedAt: row.deletedAt,
                                             warmupSeconds: row.warmupSeconds,
                                             cooldownSeconds: row.cooldownSeconds,
                                             prescribedLoadKg: row.prescribedLoadKg,
                                             activePartnerIDs: row.activePartnerIDs,
                                             updatedAt: row.updatedAt, originDevice: row.originDevice,
                                             setIDs: row.orderedSets.map(\.id)))
        }
        for row in try context.fetch(FetchDescriptor<SetEntry>()) {
            try append("SetEntry", id: row.id, updatedAt: row.updatedAt,
                        NativeSetEntry(id: row.id, weight: row.weight, reps: row.reps,
                                       order: row.order, isWarmup: row.isWarmup,
                                       usesBodyweight: row.usesBodyweight, rpe: row.rpe,
                                       note: row.note, completedAt: row.completedAt,
                                       updatedAt: row.updatedAt, originDevice: row.originDevice,
                                       barWeightKg: row.barWeightKg,
                                       loadMultiplier: row.loadMultiplier,
                                       loadAccountingMode: row.loadAccountingMode,
                                       sessionID: row.session?.id, exerciseID: row.exercise?.id,
                                       performerID: row.performedBy?.id))
        }
        for row in try context.fetch(FetchDescriptor<Exercise>()) {
            try append("Exercise", id: row.id, updatedAt: row.updatedAt,
                        NativeExercise(id: row.id, name: row.name, category: row.category,
                                       muscleGroups: row.muscleGroups, isCustom: row.isCustom,
                                       equipment: row.equipment, isLateral: row.isLateral,
                                       mechanics: row.mechanics, force: row.force,
                                       primaryMuscles: row.primaryMuscles,
                                       secondaryMuscles: row.secondaryMuscles,
                                       searchKeywords: row.searchKeywords,
                                       instructions: row.instructions, imageName: row.imageName,
                                       level: row.level, isFavorite: row.isFavorite,
                                       createdAt: row.createdAt, updatedAt: row.updatedAt,
                                       originDevice: row.originDevice,
                                       loadAccountingMode: row.loadAccountingMode,
                                       defaultBarWeightKg: row.defaultBarWeightKg,
                                       loadAccountingUserOverride: row.loadAccountingUserOverride,
                                       directMuscles: row.directMuscles.map(\.rawValue),
                                       indirectMuscles: row.indirectMuscles.map(\.rawValue),
                                       stabilizerMuscles: row.stabilizerMuscles.map(\.rawValue),
                                       trainingTypes: row.trainingTypes.map(\.rawValue),
                                       modalities: row.modalities.map(\.rawValue),
                                       sportContexts: row.sportContexts.map(\.rawValue),
                                       movementPatternIDs: row.movementPatternIDs,
                                       volumeEligible: row.volumeEligible,
                                       annotationConfidence: row.annotationConfidence,
                                       sourceExerciseID: row.sourceExerciseID))
        }
        for row in try context.fetch(FetchDescriptor<Person>()) {
            try append("Person", id: row.id, updatedAt: row.updatedAt,
                        NativePerson(id: row.id, name: row.name, isMe: row.isMe,
                                     createdAt: row.createdAt, updatedAt: row.updatedAt,
                                     originDevice: row.originDevice))
        }
        for row in try context.fetch(FetchDescriptor<SessionTemplate>()) {
            try append("SessionTemplate", id: row.id, updatedAt: row.updatedAt,
                        NativeTemplate(id: row.id, name: row.name, createdAt: row.createdAt,
                                       updatedAt: row.updatedAt, originDevice: row.originDevice,
                                       exerciseIDs: row.orderedExercises.map(\.id)))
        }
        for row in try context.fetch(FetchDescriptor<TemplateExercise>()) {
            try append("TemplateExercise", id: row.id, updatedAt: nil,
                        NativeTemplateExercise(id: row.id, exerciseName: row.exerciseName,
                                               order: row.order, targetSets: row.targetSets,
                                               targetReps: row.targetReps,
                                               templateID: row.template?.id))
        }
        for row in try context.fetch(FetchDescriptor<CardioWorkout>()) {
            try append("CardioWorkout", id: row.id, updatedAt: row.updatedAt,
                        NativeCardio(id: row.id, type: row.type, start: row.start, end: row.end,
                                    distance: row.distance, activeEnergy: row.activeEnergy,
                                    avgHeartRate: row.avgHeartRate, maxHeartRate: row.maxHeartRate,
                                    laps: row.laps, targetLaps: row.targetLaps,
                                    targetDistance: row.targetDistance, source: row.source,
                                    healthKitWorkoutUUID: row.healthKitWorkoutUUID, notes: row.notes,
                                    isLogged: row.isLogged, deletedAt: row.deletedAt,
                                    customTitle: row.customTitle,
                                    importedWorkoutKindRaw: row.importedWorkoutKindRaw,
                                    intervalDetailData: row.intervalDetailData,
                                    cardioAlgorithmVersionRaw: row.cardioAlgorithmVersionRaw,
                                    effectiveRestingHR: row.effectiveRestingHR,
                                    effectiveMaximumHR: row.effectiveMaximumHR,
                                    heartRateMaximumSourceRaw: row.heartRateMaximumSourceRaw,
                                    trainingZonePolicyRaw: row.trainingZonePolicyRaw,
                                    intensitySummaryData: row.intensitySummaryData,
                                    intensityProfileData: row.intensityProfileData,
                                    standardMETMinutes: row.standardMETMinutes,
                                    standardMETValue: row.standardMETValue,
                                    metBasisRaw: row.metBasisRaw, metMethodRaw: row.metMethodRaw,
                                    updatedAt: row.updatedAt, originDevice: row.originDevice))
        }
        for row in try context.fetch(FetchDescriptor<HRSample>()) {
            try append("HRSample", id: row.id, updatedAt: nil,
                        NativeHRSample(id: row.id, t: row.t, bpm: row.bpm, cardioID: row.cardio?.id))
        }
        for row in try context.fetch(FetchDescriptor<RouteSample>()) {
            try append("RouteSample", id: row.id, updatedAt: nil,
                        NativeRouteSample(id: row.id, t: row.t, lat: row.lat, lon: row.lon,
                                         elevation: row.elevation, cardioID: row.cardio?.id))
        }
        for row in try context.fetch(FetchDescriptor<ReadinessEntry>()) {
            try append("ReadinessEntry", id: row.id, updatedAt: row.updatedAt,
                        NativeReadiness(id: row.id, date: row.date,
                                       muscleSoreness: row.muscleSoreness,
                                       fatigueEnergy: row.fatigueEnergy,
                                       sleepQuality: row.sleepQuality, stressMood: row.stressMood,
                                       hasPainOrIllnessConcern: row.hasPainOrIllnessConcern,
                                       updatedAt: row.updatedAt))
        }
        for row in try context.fetch(FetchDescriptor<HRMDevice>()) {
            try append("HRMDevice", id: row.id, updatedAt: row.updatedAt,
                        NativeHRMDevice(id: row.id, name: row.name, lastBattery: row.lastBattery,
                                        isDefault: row.isDefault,
                                        lastConnectedAt: row.lastConnectedAt,
                                        updatedAt: row.updatedAt))
        }
        for row in try context.fetch(FetchDescriptor<Assessment>()) {
            try append("Assessment", id: row.id, updatedAt: row.updatedAt,
                        NativeAssessment(id: row.id, date: row.date, kind: row.kind,
                                        value: row.value, inputWeight: row.inputWeight,
                                        inputReps: row.inputReps, exerciseName: row.exerciseName,
                                        protocolName: row.protocolName, notes: row.notes,
                                        updatedAt: row.updatedAt, originDevice: row.originDevice,
                                        inputDistance: row.inputDistance, inputTime: row.inputTime,
                                        inputEndingHR: row.inputEndingHR, inputAge: row.inputAge,
                                        inputSex: row.inputSex))
        }
        for row in try context.fetch(FetchDescriptor<PersistedPlan>()) {
            try append("PersistedPlan", id: row.id, updatedAt: row.updatedAt,
                        NativePersistedPlan(id: row.id, payloadVersion: row.payloadVersion,
                                            planData: row.planData, updatedAt: row.updatedAt,
                                            originDevice: row.originDevice, deletedAt: row.deletedAt))
        }
        for row in try context.fetch(FetchDescriptor<PersistedPlanHeader>()) {
            try append("PersistedPlanHeader", id: row.id, updatedAt: row.updatedAt,
                        NativePlanHeader(id: row.id, title: row.title,
                                         provenanceData: row.provenanceData, goalRaw: row.goalRaw,
                                         horizonData: row.horizonData, createdAt: row.createdAt,
                                         updatedAt: row.updatedAt,
                                         authoredOnIdiomRaw: row.authoredOnIdiomRaw,
                                         statusRaw: row.statusRaw, notes: row.notes,
                                         rationaleData: row.rationaleData,
                                         originDevice: row.originDevice))
        }
        for row in try context.fetch(FetchDescriptor<PersistedPlanWeek>()) {
            try append("PersistedPlanWeek", id: row.id, updatedAt: nil,
                        NativePlanWeek(id: row.id, planID: row.planID, index: row.index,
                                       intendedProgressionRaw: row.intendedProgressionRaw,
                                       isDeload: row.isDeload))
        }
        for row in try context.fetch(FetchDescriptor<PersistedPlanDay>()) {
            try append("PersistedPlanDay", id: row.id, updatedAt: nil,
                        NativePlanDay(id: row.id, weekID: row.weekID, weekdayRaw: row.weekdayRaw))
        }
        for row in try context.fetch(FetchDescriptor<PersistedPlanSession>()) {
            try append("PersistedPlanSession", id: row.id, updatedAt: nil,
                        NativePlanSession(id: row.id, dayID: row.dayID, title: row.title,
                                          goalRaw: row.goalRaw,
                                          estimatedDurationMinutes: row.estimatedDurationMinutes,
                                          statusRaw: row.statusRaw, startedAt: row.startedAt,
                                          completedAt: row.completedAt, sessionRPE: row.sessionRPE,
                                          painData: row.painData, note: row.note,
                                          partnersData: row.partnersData))
        }
        for row in try context.fetch(FetchDescriptor<PersistedPlanItem>()) {
            try append("PersistedPlanItem", id: row.id, updatedAt: nil,
                        NativePlanItem(id: row.id, sessionID: row.sessionID, kindRaw: row.kindRaw,
                                       order: row.order, payloadData: row.payloadData))
        }
        for row in try context.fetch(FetchDescriptor<PersistedPlanSet>()) {
            try append("PersistedPlanSet", id: row.id, updatedAt: nil,
                        NativePlanSet(id: row.id, itemID: row.itemID, setIndex: row.setIndex,
                                      payloadData: row.payloadData))
        }
        for row in try context.fetch(FetchDescriptor<PersistedClientRelationship>()) {
            try append("PersistedClientRelationship", id: row.id, updatedAt: row.updatedAt,
                        NativeClientRelationship(id: row.id, displayName: row.displayName,
                                                 notes: row.notes, goalRaw: row.goalRaw,
                                                 statusRaw: row.statusRaw, shareZoneID: row.shareZoneID,
                                                 shareURLString: row.shareURLString,
                                                 createdAt: row.createdAt, updatedAt: row.updatedAt))
        }
        for row in try context.fetch(FetchDescriptor<ExerciseSuggestionExclusion>()) {
            try append("ExerciseSuggestionExclusion", id: row.id, updatedAt: row.updatedAt,
                        NativeSuggestionExclusion(id: row.id, exerciseKey: row.exerciseKey,
                                                  exerciseNameSnapshot: row.exerciseNameSnapshot,
                                                  reasonRaw: row.reasonRaw, isActive: row.isActive,
                                                  createdAt: row.createdAt, updatedAt: row.updatedAt,
                                                  originDevice: row.originDevice))
        }
        for row in try context.fetch(FetchDescriptor<ScheduledWorkout>()) {
            try append("ScheduledWorkout", id: row.id, updatedAt: row.updatedAt,
                        NativeScheduledWorkout(id: row.id, scheduledDate: row.scheduledDate,
                                               scheduledDayKey: row.scheduledDayKey,
                                               timeZoneIdentifier: row.timeZoneIdentifier,
                                               title: row.title, payloadData: row.payloadData,
                                               payloadVersion: row.payloadVersion,
                                               statusRaw: row.statusRaw,
                                               startedSessionID: row.startedSessionID,
                                               createdAt: row.createdAt, updatedAt: row.updatedAt,
                                               deletedAt: row.deletedAt,
                                               originDevice: row.originDevice))
        }

        return ExportNativeDatabase(records: records)
    }

    /// Imports the additive archive after the legacy arrays. The operation is
    /// ID-based and idempotent; existing rows are only updated when the archive
    /// carries a newer timestamp.
    @discardableResult
    public static func merge(_ archive: ExportNativeDatabase,
                             in context: ModelContext) throws -> Int {
        guard archive.schemaVersion <= ExportNativeDatabase.schemaVersion else { return 0 }
        var changed = 0
        let records = archive.records

        func record(_ entity: String, _ id: UUID) -> ExportNativeRecord? {
            records.first { $0.entity == entity && $0.id == id }
        }
        func shouldApply(_ incoming: Date?, existing: Date) -> Bool {
            guard let incoming else { return true }
            return incoming >= existing
        }

        var peopleByID: [UUID: Person] = [:]
        for row in try context.fetch(FetchDescriptor<Person>()) { peopleByID[row.id] = row }
        for record in records where record.entity == "Person" {
            let value = try NativeArchiveCodec.decode(NativePerson.self, from: record.payload)
            if let existing = peopleByID[value.id] {
                guard shouldApply(value.updatedAt, existing: existing.updatedAt) else { continue }
                existing.name = value.name; existing.isMe = value.isMe
                existing.createdAt = value.createdAt; existing.updatedAt = value.updatedAt
                existing.originDevice = value.originDevice
            } else {
                let person = Person(id: value.id, name: value.name, isMe: value.isMe,
                                    createdAt: value.createdAt, updatedAt: value.updatedAt,
                                    originDevice: value.originDevice)
                context.insert(person); peopleByID[value.id] = person; changed += 1
            }
        }

        var exercisesByID: [UUID: Exercise] = [:]
        for row in try context.fetch(FetchDescriptor<Exercise>()) { exercisesByID[row.id] = row }
        for record in records where record.entity == "Exercise" {
            let value = try NativeArchiveCodec.decode(NativeExercise.self, from: record.payload)
            let exercise: Exercise
            if let existing = exercisesByID[value.id] {
                guard shouldApply(value.updatedAt, existing: existing.updatedAt) else { continue }
                exercise = existing
            } else {
                exercise = Exercise(id: value.id, name: value.name,
                                    category: value.category.flatMap(ExerciseCategory.init(rawValue:)),
                                    muscleGroups: value.muscleGroups, isCustom: value.isCustom,
                                    equipment: value.equipment.flatMap(Equipment.init(rawValue:)),
                                    isLateral: value.isLateral,
                                    mechanics: value.mechanics.flatMap(Mechanics.init(rawValue:)),
                                    force: value.force.flatMap(Force.init(rawValue:)),
                                    primaryMuscles: value.primaryMuscles,
                                    secondaryMuscles: value.secondaryMuscles,
                                    searchKeywords: value.searchKeywords,
                                    instructions: value.instructions, imageName: value.imageName,
                                    level: value.level, isFavorite: value.isFavorite,
                                    createdAt: value.createdAt, updatedAt: value.updatedAt,
                                    originDevice: value.originDevice,
                                    loadAccountingMode: value.loadAccountingMode.flatMap(LoadAccountingMode.init(rawValue:)),
                                    defaultBarWeightKg: value.defaultBarWeightKg,
                                    loadAccountingUserOverride: value.loadAccountingUserOverride,
                                    directMuscles: MuscleGroup.canonicalize(value.directMuscles),
                                    indirectMuscles: MuscleGroup.canonicalize(value.indirectMuscles),
                                    stabilizerMuscles: MuscleGroup.canonicalize(value.stabilizerMuscles),
                                    trainingTypes: ExerciseTrainingType.decode(value.trainingTypes),
                                    modalities: ExerciseModality.decode(value.modalities),
                                    sportContexts: ExerciseSportContext.decode(value.sportContexts),
                                    movementPatternIDs: value.movementPatternIDs,
                                    volumeEligible: value.volumeEligible,
                                    annotationConfidence: value.annotationConfidence.flatMap(AnnotationConfidence.init(rawValue:)),
                                    sourceExerciseID: value.sourceExerciseID)
                context.insert(exercise); exercisesByID[value.id] = exercise; changed += 1
                continue
            }
            exercise.name = value.name; exercise.category = value.category
            exercise.muscleGroups = value.muscleGroups; exercise.isCustom = value.isCustom
            exercise.equipment = value.equipment; exercise.isLateral = value.isLateral
            exercise.mechanics = value.mechanics; exercise.force = value.force
            exercise.primaryMuscles = value.primaryMuscles; exercise.secondaryMuscles = value.secondaryMuscles
            exercise.searchKeywords = value.searchKeywords; exercise.instructions = value.instructions
            exercise.imageName = value.imageName; exercise.level = value.level
            exercise.isFavorite = value.isFavorite; exercise.createdAt = value.createdAt
            exercise.updatedAt = value.updatedAt; exercise.originDevice = value.originDevice
            exercise.loadAccountingMode = value.loadAccountingMode
            exercise.defaultBarWeightKg = value.defaultBarWeightKg
            exercise.loadAccountingUserOverride = value.loadAccountingUserOverride
            exercise.directMuscles = MuscleGroup.canonicalize(value.directMuscles)
            exercise.indirectMuscles = MuscleGroup.canonicalize(value.indirectMuscles)
            exercise.stabilizerMuscles = MuscleGroup.canonicalize(value.stabilizerMuscles)
            exercise.trainingTypes = ExerciseTrainingType.decode(value.trainingTypes)
            exercise.modalities = ExerciseModality.decode(value.modalities)
            exercise.sportContexts = ExerciseSportContext.decode(value.sportContexts)
            exercise.movementPatternIDs = value.movementPatternIDs
            exercise.volumeEligible = value.volumeEligible
            exercise.annotationConfidence = value.annotationConfidence
            exercise.sourceExerciseID = value.sourceExerciseID
        }

        var sessionsByID: [UUID: WorkoutSession] = [:]
        for row in try context.fetch(FetchDescriptor<WorkoutSession>()) { sessionsByID[row.id] = row }
        for record in records where record.entity == "WorkoutSession" {
            let value = try NativeArchiveCodec.decode(NativeWorkoutSession.self, from: record.payload)
            let session: WorkoutSession
            if let existing = sessionsByID[value.id] {
                guard shouldApply(value.updatedAt, existing: existing.updatedAt) else { continue }
                session = existing
            } else {
                session = WorkoutSession(id: value.id, title: value.title, date: value.date,
                                         endedAt: value.endedAt, notes: value.notes,
                                         templateName: value.templateName,
                                         healthKitWorkoutUUID: value.healthKitWorkoutUUID,
                                         isLogged: value.isLogged, warmupSeconds: value.warmupSeconds,
                                         cooldownSeconds: value.cooldownSeconds,
                                         activePartnerIDsData: StringArray.encode(value.activePartnerIDs),
                                         planSessionID: value.planSessionID,
                                         scheduledWorkoutID: value.scheduledWorkoutID,
                                         updatedAt: value.updatedAt, originDevice: value.originDevice)
                context.insert(session); sessionsByID[value.id] = session; changed += 1
            }
            session.title = value.title; session.date = value.date; session.endedAt = value.endedAt
            session.plannedExerciseNames = value.plannedExerciseNames
            session.plannedRepLadder = value.plannedRepLadder
            session.plannedPrescriptions = value.plannedPrescriptions
            session.plannedPerformerPrescriptions = value.plannedPerformerPrescriptions.map {
                PlannedPerformerPrescription(performerID: $0.performerID, exercises: $0.exercises)
            }
            session.notes = value.notes; session.templateName = value.templateName
            session.planKey = value.planKey; session.enginePlanId = value.enginePlanId
            session.engineRevisionId = value.engineRevisionId; session.enginePlanJSON = value.enginePlanJSON
            session.planSessionID = value.planSessionID; session.scheduledWorkoutID = value.scheduledWorkoutID
            session.healthKitWorkoutUUID = value.healthKitWorkoutUUID; session.isLogged = value.isLogged
            session.deletedAt = value.deletedAt; session.warmupSeconds = value.warmupSeconds
            session.cooldownSeconds = value.cooldownSeconds; session.prescribedLoadKg = value.prescribedLoadKg
            session.activePartnerIDs = value.activePartnerIDs; session.updatedAt = value.updatedAt
            session.originDevice = value.originDevice
        }

        var setsByID: [UUID: SetEntry] = [:]
        for row in try context.fetch(FetchDescriptor<SetEntry>()) { setsByID[row.id] = row }
        for record in records where record.entity == "SetEntry" {
            let value = try NativeArchiveCodec.decode(NativeSetEntry.self, from: record.payload)
            let set: SetEntry
            if let existing = setsByID[value.id] {
                guard shouldApply(value.updatedAt, existing: existing.updatedAt) else { continue }
                set = existing
            } else {
                set = SetEntry(id: value.id, weight: value.weight, reps: value.reps, order: value.order,
                               isWarmup: value.isWarmup, usesBodyweight: value.usesBodyweight,
                               rpe: value.rpe, note: value.note, completedAt: value.completedAt,
                               updatedAt: value.updatedAt, originDevice: value.originDevice,
                               session: value.sessionID.flatMap { sessionsByID[$0] },
                               exercise: value.exerciseID.flatMap { exercisesByID[$0] },
                               performedBy: value.performerID.flatMap { peopleByID[$0] },
                               barWeightKg: value.barWeightKg, loadMultiplier: value.loadMultiplier,
                               loadAccountingMode: value.loadAccountingMode)
                context.insert(set); setsByID[value.id] = set; changed += 1
            }
            set.weight = value.weight; set.reps = value.reps; set.order = value.order
            set.isWarmup = value.isWarmup; set.usesBodyweight = value.usesBodyweight
            set.rpe = value.rpe; set.note = value.note; set.completedAt = value.completedAt
            set.updatedAt = value.updatedAt; set.originDevice = value.originDevice
            set.barWeightKg = value.barWeightKg; set.loadMultiplier = value.loadMultiplier
            set.loadAccountingMode = value.loadAccountingMode
            set.session = value.sessionID.flatMap { sessionsByID[$0] }
            set.exercise = value.exerciseID.flatMap { exercisesByID[$0] }
            set.performedBy = value.performerID.flatMap { peopleByID[$0] }
        }

        try mergeCardio(records, in: context, changed: &changed)
        try mergeSimple(records, in: context, changed: &changed)
        try context.save()
        return changed
    }

    private static func mergeCardio(_ records: [ExportNativeRecord], in context: ModelContext,
                                    changed: inout Int) throws {
        var cardios = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CardioWorkout>()).map { ($0.id, $0) })
        for record in records where record.entity == "CardioWorkout" {
            let value = try NativeArchiveCodec.decode(NativeCardio.self, from: record.payload)
            let cardio: CardioWorkout
            if let existing = cardios[value.id] {
                guard value.updatedAt >= existing.updatedAt else { continue }
                cardio = existing
            } else {
                cardio = CardioWorkout(id: value.id, type: CardioType(rawValue: value.type) ?? .other,
                                       start: value.start, end: value.end, distance: value.distance,
                                       activeEnergy: value.activeEnergy, avgHeartRate: value.avgHeartRate,
                                       maxHeartRate: value.maxHeartRate,
                                       laps: value.laps, targetLaps: value.targetLaps,
                                       targetDistance: value.targetDistance,
                                       source: CardioSource(rawValue: value.source) ?? .iphone,
                                       healthKitWorkoutUUID: value.healthKitWorkoutUUID, notes: value.notes,
                                       isLogged: value.isLogged, customTitle: value.customTitle,
                                       importedWorkoutKind: value.importedWorkoutKindRaw.flatMap(ImportedWorkoutKind.init(rawValue:)),
                                       updatedAt: value.updatedAt, originDevice: value.originDevice)
                context.insert(cardio); cardios[value.id] = cardio; changed += 1
            }
            cardio.type = value.type; cardio.start = value.start; cardio.end = value.end
            cardio.distance = value.distance; cardio.activeEnergy = value.activeEnergy
            cardio.avgHeartRate = value.avgHeartRate; cardio.maxHeartRate = value.maxHeartRate
            cardio.laps = value.laps; cardio.targetLaps = value.targetLaps; cardio.targetDistance = value.targetDistance
            cardio.source = value.source; cardio.healthKitWorkoutUUID = value.healthKitWorkoutUUID
            cardio.notes = value.notes; cardio.isLogged = value.isLogged; cardio.deletedAt = value.deletedAt
            cardio.customTitle = value.customTitle; cardio.importedWorkoutKindRaw = value.importedWorkoutKindRaw
            cardio.intervalDetailData = value.intervalDetailData; cardio.cardioAlgorithmVersionRaw = value.cardioAlgorithmVersionRaw
            cardio.effectiveRestingHR = value.effectiveRestingHR; cardio.effectiveMaximumHR = value.effectiveMaximumHR
            cardio.heartRateMaximumSourceRaw = value.heartRateMaximumSourceRaw
            cardio.trainingZonePolicyRaw = value.trainingZonePolicyRaw
            cardio.intensitySummaryData = value.intensitySummaryData; cardio.intensityProfileData = value.intensityProfileData
            cardio.standardMETMinutes = value.standardMETMinutes; cardio.standardMETValue = value.standardMETValue
            cardio.metBasisRaw = value.metBasisRaw; cardio.metMethodRaw = value.metMethodRaw
            cardio.updatedAt = value.updatedAt; cardio.originDevice = value.originDevice
        }
        let existingSamples = try context.fetch(FetchDescriptor<HRSample>())
        var samples = Dictionary(uniqueKeysWithValues: existingSamples.map { ($0.id, $0) })
        for record in records where record.entity == "HRSample" {
            let value = try NativeArchiveCodec.decode(NativeHRSample.self, from: record.payload)
            if let existing = samples[value.id] {
                existing.t = value.t; existing.bpm = value.bpm
                existing.cardio = value.cardioID.flatMap { cardios[$0] }
            } else if let existing = existingSamples.first(where: {
                $0.t == value.t && $0.bpm == value.bpm && $0.cardio?.id == value.cardioID
            }) {
                // The legacy nested cardio export did not preserve sample IDs.
                // Match its rows by stable content so importing v8 cannot create
                // duplicate heart-rate samples beside the native archive.
                samples[value.id] = existing
                existing.cardio = value.cardioID.flatMap { cardios[$0] }
            } else {
                let sample = HRSample(id: value.id, t: value.t, bpm: value.bpm,
                                      cardio: value.cardioID.flatMap { cardios[$0] })
                context.insert(sample)
                samples[value.id] = sample
                changed += 1
            }
        }
        let existingRoutes = try context.fetch(FetchDescriptor<RouteSample>())
        var routes = Dictionary(uniqueKeysWithValues: existingRoutes.map { ($0.id, $0) })
        for record in records where record.entity == "RouteSample" {
            let value = try NativeArchiveCodec.decode(NativeRouteSample.self, from: record.payload)
            if let existing = routes[value.id] {
                existing.t = value.t; existing.lat = value.lat; existing.lon = value.lon
                existing.elevation = value.elevation; existing.cardio = value.cardioID.flatMap { cardios[$0] }
            } else if let existing = existingRoutes.first(where: {
                $0.t == value.t && $0.lat == value.lat && $0.lon == value.lon &&
                $0.elevation == value.elevation && $0.cardio?.id == value.cardioID
            }) {
                // Same compatibility path as HRSample above for legacy exports.
                routes[value.id] = existing
                existing.cardio = value.cardioID.flatMap { cardios[$0] }
            } else {
                let route = RouteSample(id: value.id, t: value.t, lat: value.lat, lon: value.lon,
                                        elevation: value.elevation,
                                        cardio: value.cardioID.flatMap { cardios[$0] })
                context.insert(route)
                routes[value.id] = route
                changed += 1
            }
        }
    }

    private static func mergeSimple(_ records: [ExportNativeRecord], in context: ModelContext,
                                    changed: inout Int) throws {
        var readiness = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ReadinessEntry>()).map { ($0.id, $0) })
        for record in records where record.entity == "ReadinessEntry" {
            let v = try NativeArchiveCodec.decode(NativeReadiness.self, from: record.payload)
            let row = readiness[v.id] ?? ReadinessEntry(id: v.id)
            row.date = v.date; row.muscleSoreness = v.muscleSoreness; row.fatigueEnergy = v.fatigueEnergy
            row.sleepQuality = v.sleepQuality; row.stressMood = v.stressMood
            row.hasPainOrIllnessConcern = v.hasPainOrIllnessConcern; row.updatedAt = v.updatedAt
            if readiness[v.id] == nil { context.insert(row); readiness[v.id] = row; changed += 1 }
        }
        var devices = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<HRMDevice>()).map { ($0.id, $0) })
        for record in records where record.entity == "HRMDevice" {
            let v = try NativeArchiveCodec.decode(NativeHRMDevice.self, from: record.payload)
            let row = devices[v.id] ?? HRMDevice(id: v.id)
            row.name = v.name; row.lastBattery = v.lastBattery; row.isDefault = v.isDefault
            row.lastConnectedAt = v.lastConnectedAt; row.updatedAt = v.updatedAt
            if devices[v.id] == nil { context.insert(row); devices[v.id] = row; changed += 1 }
        }
        var assessments = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Assessment>()).map { ($0.id, $0) })
        for record in records where record.entity == "Assessment" {
            let v = try NativeArchiveCodec.decode(NativeAssessment.self, from: record.payload)
            let row = assessments[v.id] ?? Assessment(id: v.id)
            row.date = v.date; row.kind = v.kind; row.value = v.value; row.inputWeight = v.inputWeight
            row.inputReps = v.inputReps; row.exerciseName = v.exerciseName; row.protocolName = v.protocolName
            row.notes = v.notes; row.updatedAt = v.updatedAt; row.originDevice = v.originDevice
            row.inputDistance = v.inputDistance; row.inputTime = v.inputTime; row.inputEndingHR = v.inputEndingHR
            row.inputAge = v.inputAge; row.inputSex = v.inputSex
            if assessments[v.id] == nil { context.insert(row); assessments[v.id] = row; changed += 1 }
        }
        try mergeTemplates(records, in: context, changed: &changed)
        try mergeScheduled(records, in: context, changed: &changed)
        try mergePlanRows(records, in: context, changed: &changed)
        try mergeExclusions(records, in: context, changed: &changed)
    }

    private static func mergeTemplates(_ records: [ExportNativeRecord], in context: ModelContext,
                                       changed: inout Int) throws {
        var templates = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<SessionTemplate>()).map { ($0.id, $0) })
        for record in records where record.entity == "SessionTemplate" {
            let v = try NativeArchiveCodec.decode(NativeTemplate.self, from: record.payload)
            let row = templates[v.id] ?? SessionTemplate(id: v.id, name: v.name,
                                                          createdAt: v.createdAt, updatedAt: v.updatedAt,
                                                          originDevice: v.originDevice)
            row.name = v.name; row.createdAt = v.createdAt; row.updatedAt = v.updatedAt; row.originDevice = v.originDevice
            if templates[v.id] == nil { context.insert(row); templates[v.id] = row; changed += 1 }
        }
        var children = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateExercise>()).map { ($0.id, $0) })
        for record in records where record.entity == "TemplateExercise" {
            let v = try NativeArchiveCodec.decode(NativeTemplateExercise.self, from: record.payload)
            let row = children[v.id] ?? TemplateExercise(id: v.id)
            row.exerciseName = v.exerciseName; row.order = v.order; row.targetSets = v.targetSets
            row.targetReps = v.targetReps; row.template = v.templateID.flatMap { templates[$0] }
            if children[v.id] == nil { context.insert(row); children[v.id] = row; changed += 1 }
        }
    }

    private static func mergeScheduled(_ records: [ExportNativeRecord], in context: ModelContext,
                                       changed: inout Int) throws {
        var rows = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ScheduledWorkout>()).map { ($0.id, $0) })
        for record in records where record.entity == "ScheduledWorkout" {
            let v = try NativeArchiveCodec.decode(NativeScheduledWorkout.self, from: record.payload)
            let row = rows[v.id] ?? ScheduledWorkout(id: v.id)
            row.scheduledDate = v.scheduledDate; row.scheduledDayKey = v.scheduledDayKey
            row.timeZoneIdentifier = v.timeZoneIdentifier; row.title = v.title; row.payloadData = v.payloadData
            row.payloadVersion = v.payloadVersion; row.statusRaw = v.statusRaw; row.startedSessionID = v.startedSessionID
            row.createdAt = v.createdAt; row.updatedAt = v.updatedAt; row.deletedAt = v.deletedAt; row.originDevice = v.originDevice
            if rows[v.id] == nil { context.insert(row); rows[v.id] = row; changed += 1 }
        }
    }

    private static func mergePlanRows(_ records: [ExportNativeRecord], in context: ModelContext,
                                      changed: inout Int) throws {
        for record in records where record.entity == "PersistedPlan" {
            let v = try NativeArchiveCodec.decode(NativePersistedPlan.self, from: record.payload)
            let row = try context.fetch(FetchDescriptor<PersistedPlan>(predicate: #Predicate { $0.id == v.id })).first
                ?? PersistedPlan(id: v.id)
            row.payloadVersion = v.payloadVersion; row.planData = v.planData; row.updatedAt = v.updatedAt
            row.originDevice = v.originDevice; row.deletedAt = v.deletedAt
            if row.modelContext == nil { context.insert(row); changed += 1 }
        }
        for record in records where record.entity == "PersistedPlanHeader" {
            let v = try NativeArchiveCodec.decode(NativePlanHeader.self, from: record.payload)
            let row = try context.fetch(FetchDescriptor<PersistedPlanHeader>(predicate: #Predicate { $0.id == v.id })).first
                ?? PersistedPlanHeader(id: v.id)
            row.title = v.title; row.provenanceData = v.provenanceData; row.goalRaw = v.goalRaw; row.horizonData = v.horizonData
            row.createdAt = v.createdAt; row.updatedAt = v.updatedAt; row.authoredOnIdiomRaw = v.authoredOnIdiomRaw
            row.statusRaw = v.statusRaw; row.notes = v.notes; row.rationaleData = v.rationaleData; row.originDevice = v.originDevice
            if row.modelContext == nil { context.insert(row); changed += 1 }
        }
        for record in records where record.entity == "PersistedPlanWeek" {
            let v = try NativeArchiveCodec.decode(NativePlanWeek.self, from: record.payload)
            let row = try context.fetch(FetchDescriptor<PersistedPlanWeek>(predicate: #Predicate { $0.id == v.id })).first
                ?? PersistedPlanWeek(id: v.id)
            row.planID = v.planID; row.index = v.index; row.intendedProgressionRaw = v.intendedProgressionRaw; row.isDeload = v.isDeload
            if row.modelContext == nil { context.insert(row); changed += 1 }
        }
        for record in records where record.entity == "PersistedPlanDay" {
            let v = try NativeArchiveCodec.decode(NativePlanDay.self, from: record.payload)
            let row = try context.fetch(FetchDescriptor<PersistedPlanDay>(predicate: #Predicate { $0.id == v.id })).first
                ?? PersistedPlanDay(id: v.id)
            row.weekID = v.weekID; row.weekdayRaw = v.weekdayRaw
            if row.modelContext == nil { context.insert(row); changed += 1 }
        }
        for record in records where record.entity == "PersistedPlanSession" {
            let v = try NativeArchiveCodec.decode(NativePlanSession.self, from: record.payload)
            let row = try context.fetch(FetchDescriptor<PersistedPlanSession>(predicate: #Predicate { $0.id == v.id })).first
                ?? PersistedPlanSession(id: v.id)
            row.dayID = v.dayID; row.title = v.title; row.goalRaw = v.goalRaw; row.estimatedDurationMinutes = v.estimatedDurationMinutes
            row.statusRaw = v.statusRaw; row.startedAt = v.startedAt; row.completedAt = v.completedAt; row.sessionRPE = v.sessionRPE
            row.painData = v.painData; row.note = v.note; row.partnersData = v.partnersData
            if row.modelContext == nil { context.insert(row); changed += 1 }
        }
        for record in records where record.entity == "PersistedPlanItem" {
            let v = try NativeArchiveCodec.decode(NativePlanItem.self, from: record.payload)
            let row = try context.fetch(FetchDescriptor<PersistedPlanItem>(predicate: #Predicate { $0.id == v.id })).first
                ?? PersistedPlanItem(id: v.id)
            row.sessionID = v.sessionID; row.kindRaw = v.kindRaw; row.order = v.order; row.payloadData = v.payloadData
            if row.modelContext == nil { context.insert(row); changed += 1 }
        }
        for record in records where record.entity == "PersistedPlanSet" {
            let v = try NativeArchiveCodec.decode(NativePlanSet.self, from: record.payload)
            let row = try context.fetch(FetchDescriptor<PersistedPlanSet>(predicate: #Predicate { $0.id == v.id })).first
                ?? PersistedPlanSet(id: v.id)
            row.itemID = v.itemID; row.setIndex = v.setIndex; row.payloadData = v.payloadData
            if row.modelContext == nil { context.insert(row); changed += 1 }
        }
        for record in records where record.entity == "PersistedClientRelationship" {
            let v = try NativeArchiveCodec.decode(NativeClientRelationship.self, from: record.payload)
            let row = try context.fetch(FetchDescriptor<PersistedClientRelationship>(predicate: #Predicate { $0.id == v.id })).first
                ?? PersistedClientRelationship(id: v.id)
            row.displayName = v.displayName; row.notes = v.notes; row.goalRaw = v.goalRaw; row.statusRaw = v.statusRaw
            row.shareZoneID = v.shareZoneID; row.shareURLString = v.shareURLString; row.createdAt = v.createdAt; row.updatedAt = v.updatedAt
            if row.modelContext == nil { context.insert(row); changed += 1 }
        }
    }

    private static func mergeExclusions(_ records: [ExportNativeRecord], in context: ModelContext,
                                        changed: inout Int) throws {
        var rows = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ExerciseSuggestionExclusion>()).map { ($0.id, $0) })
        for record in records where record.entity == "ExerciseSuggestionExclusion" {
            let v = try NativeArchiveCodec.decode(NativeSuggestionExclusion.self, from: record.payload)
            let row = rows[v.id] ?? ExerciseSuggestionExclusion(id: v.id)
            row.exerciseKey = v.exerciseKey; row.exerciseNameSnapshot = v.exerciseNameSnapshot; row.reasonRaw = v.reasonRaw
            row.isActive = v.isActive; row.createdAt = v.createdAt; row.updatedAt = v.updatedAt; row.originDevice = v.originDevice
            if rows[v.id] == nil { context.insert(row); rows[v.id] = row; changed += 1 }
        }
    }
}
