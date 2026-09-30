import Foundation

/// The small, Foundation-only payload produced by the HealthKit adapter. The
/// adapter owns HealthKit objects; this value owns the restore contract so it
/// can be tested on macOS and used by future non-HealthKit adapters.
public enum HealthBackupSource: String, Codable, Equatable, Sendable {
    case iphone
    case watch
    case other
}

public enum HealthWorkoutPayloadKind: String, Codable, Equatable, Sendable {
    case strength
    case cardio
}

public struct HealthWorkoutReadPayload: Codable, Equatable, Sendable {
    public let healthObjectID: UUID
    public let kind: HealthWorkoutPayloadKind
    public let activityType: ImportedWorkoutKind
    public let start: Date
    public let end: Date
    public let activeEnergyKcal: Double?
    public let distanceMeters: Double?
    public let heartRate: [HRSamplePoint]
    public let route: [LocationFix]
    public let metadata: [String: String]
    public let source: HealthBackupSource

    public init(healthObjectID: UUID, kind: HealthWorkoutPayloadKind,
                activityType: ImportedWorkoutKind, start: Date, end: Date,
                activeEnergyKcal: Double? = nil, distanceMeters: Double? = nil,
                heartRate: [HRSamplePoint] = [], route: [LocationFix] = [],
                metadata: [String: String] = [:], source: HealthBackupSource) {
        self.healthObjectID = healthObjectID
        self.kind = kind
        self.activityType = activityType
        self.start = start
        self.end = end
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceMeters = distanceMeters
        self.heartRate = heartRate
        self.route = route
        self.metadata = metadata
        self.source = source
    }
}

public struct HealthVO2ReadPayload: Codable, Equatable, Sendable {
    public let healthObjectID: UUID
    public let date: Date
    public let value: Double
    public let metadata: [String: String]
    public let source: HealthBackupSource

    public init(healthObjectID: UUID, date: Date, value: Double,
                metadata: [String: String] = [:], source: HealthBackupSource) {
        self.healthObjectID = healthObjectID
        self.date = date
        self.value = value
        self.metadata = metadata
        self.source = source
    }
}

public struct LegacyHealthWorkoutSummary: Codable, Equatable, Sendable {
    public let healthObjectID: UUID
    public let activityType: ImportedWorkoutKind
    public let start: Date
    public let end: Date
    public let activeEnergyKcal: Double?
    public let source: HealthBackupSource

    public init(healthObjectID: UUID, activityType: ImportedWorkoutKind,
                start: Date, end: Date, activeEnergyKcal: Double?,
                source: HealthBackupSource) {
        self.healthObjectID = healthObjectID
        self.activityType = activityType
        self.start = start
        self.end = end
        self.activeEnergyKcal = activeEnergyKcal
        self.source = source
    }
}

/// A decoded object that is safe to merge into the local store. Partner sets
/// are never representable here: the strength payload contains only the owner
/// set metadata written by `HealthBackupEncoder`.
public enum HealthBackupReadObject: Codable, Equatable, Sendable {
    case strength(summary: StrengthWorkoutSummary, healthObjectID: UUID,
                  source: HealthBackupSource)
    case cardio(summary: CardioWorkoutSummary, healthObjectID: UUID,
                source: HealthBackupSource)
    case assessment(payload: HealthAssessmentPayload, healthObjectID: UUID,
                    source: HealthBackupSource)
    case legacySummary(LegacyHealthWorkoutSummary)

    public var entityKind: HealthBackupEntityKind {
        switch self {
        case .strength: return .strengthSession
        case .cardio: return .cardioWorkout
        case .assessment: return .assessment
        case .legacySummary: return .strengthSession
        }
    }

    /// The stable Cladiron sync ID, or the Health object ID for a pre-H3 object.
    public var entityID: UUID {
        switch self {
        case .strength(let summary, _, _): return summary.id
        case .cardio(let summary, _, _): return summary.id
        case .assessment(let payload, _, _): return payload.id
        case .legacySummary(let summary): return summary.healthObjectID
        }
    }

    public var healthObjectID: UUID {
        switch self {
        case .strength(_, let id, _): return id
        case .cardio(_, let id, _): return id
        case .assessment(_, let id, _): return id
        case .legacySummary(let summary): return summary.healthObjectID
        }
    }

    public var updatedAt: Date {
        switch self {
        case .strength(let summary, _, _): return summary.updatedAt ?? summary.end
        case .cardio(let summary, _, _): return summary.updatedAt ?? summary.end
        case .assessment(let payload, _, _): return payload.updatedAt
        case .legacySummary(let summary): return summary.end
        }
    }

    public var source: HealthBackupSource {
        switch self {
        case .strength(_, _, let source): return source
        case .cardio(_, _, let source): return source
        case .assessment(_, _, let source): return source
        case .legacySummary(let summary): return summary.source
        }
    }

    public var isLegacy: Bool {
        if case .legacySummary = self { return true }
        return false
    }
}

public enum HealthBackupDecodeError: Error, Equatable, Sendable {
    case unknownSchema(Int)
    case missingSyncIdentifier
    case invalidSyncIdentifier
    case invalidAssessment
    case invalidOwnerSets
}

/// Converts plain HealthKit-adapter values into the strict restore payload.
/// Unknown Cladiron schema versions fail visibly so a newer app never silently
/// imports a partial workout.
public enum HealthBackupDecoder {
    public static func workout(_ payload: HealthWorkoutReadPayload) throws -> HealthBackupReadObject {
        guard let rawSchema = payload.metadata[CladironHealthBackup.schemaKey] else {
            let legacy = LegacyHealthWorkoutSummary(
                healthObjectID: payload.healthObjectID,
                activityType: payload.activityType,
                start: payload.start,
                end: payload.end,
                activeEnergyKcal: payload.activeEnergyKcal,
                source: payload.source)
            return .legacySummary(legacy)
        }
        guard let schema = Int(rawSchema), schema == CladironHealthBackup.schemaVersion else {
            throw HealthBackupDecodeError.unknownSchema(Int(rawSchema) ?? -1)
        }
        guard let rawID = payload.metadata[CladironHealthBackup.syncIdentifierKey] else {
            throw HealthBackupDecodeError.missingSyncIdentifier
        }
        guard let id = UUID(uuidString: rawID) else {
            throw HealthBackupDecodeError.invalidSyncIdentifier
        }

        if let rawAssessmentKind = payload.metadata[CladironHealthBackup.assessmentKindKey],
           let value = Double(payload.metadata[CladironHealthBackup.assessmentValueKey] ?? "") {
            let inputDistance = payload.metadata[CladironHealthBackup.assessmentInputDistanceKey].flatMap(Double.init)
            let inputTime = payload.metadata[CladironHealthBackup.assessmentInputTimeKey].flatMap(Double.init)
            let inputEndingHR = payload.metadata[CladironHealthBackup.assessmentInputEndingHRKey].flatMap(Double.init)
            let inputWeight = payload.metadata[CladironHealthBackup.assessmentInputWeightKey].flatMap(Double.init) ?? 0
            let inputReps = payload.metadata[CladironHealthBackup.assessmentInputRepsKey].flatMap(Int.init) ?? 0
            let inputAge = payload.metadata[CladironHealthBackup.assessmentInputAgeKey].flatMap(Int.init)
            let inputSex = payload.metadata[CladironHealthBackup.assessmentInputSexKey].flatMap(Int.init)
            let syncDate = date(for: payload.metadata[CladironHealthBackup.syncVersionKey]) ?? payload.end
            let assessment = HealthAssessmentPayload(
                id: id,
                date: payload.start,
                kind: rawAssessmentKind,
                value: value,
                inputWeight: inputWeight,
                inputReps: inputReps,
                exerciseName: payload.metadata[CladironHealthBackup.assessmentExerciseNameKey],
                protocolName: payload.metadata[CladironHealthBackup.assessmentProtocolKey],
                notes: payload.metadata[CladironHealthBackup.assessmentNotesKey],
                updatedAt: syncDate,
                inputDistance: inputDistance,
                inputTime: inputTime,
                inputEndingHR: inputEndingHR,
                inputAge: inputAge,
                inputSex: inputSex)
            return .assessment(payload: assessment, healthObjectID: payload.healthObjectID,
                               source: payload.source)
        }

        let updatedAt = date(for: payload.metadata[CladironHealthBackup.syncVersionKey]) ?? payload.end
        switch payload.kind {
        case .strength:
            let ownerSets = try decodeOwnerSets(payload.metadata[CladironHealthBackup.ownerSetsKey])
            var metadata = payload.metadata
            metadata[CladironHealthBackup.schemaKey] = String(CladironHealthBackup.schemaVersion)
            let summary = StrengthWorkoutSummary(
                id: id,
                start: payload.start,
                end: payload.end,
                activeEnergyKcal: payload.activeEnergyKcal,
                hrSamples: payload.heartRate,
                avgHR: average(payload.heartRate),
                maxHR: payload.heartRate.map(\.bpm).max(),
                metadata: metadata,
                updatedAt: updatedAt)
            if ownerSets.isEmpty, payload.metadata[CladironHealthBackup.ownerSetsKey] != nil {
                throw HealthBackupDecodeError.invalidOwnerSets
            }
            return .strength(summary: summary, healthObjectID: payload.healthObjectID,
                            source: payload.source)
        case .cardio:
            let type = cardioType(for: payload.activityType)
            let summary = CardioWorkoutSummary(
                id: id,
                type: type,
                start: payload.start,
                end: payload.end,
                distanceMeters: payload.distanceMeters,
                activeEnergyKcal: payload.activeEnergyKcal,
                hrSamples: payload.heartRate,
                route: payload.route,
                customTitle: payload.metadata[CladironHealthBackup.titleKey],
                updatedAt: updatedAt)
            return .cardio(summary: summary, healthObjectID: payload.healthObjectID,
                           source: payload.source)
        }
    }

    public static func vo2(_ payload: HealthVO2ReadPayload) throws -> HealthBackupReadObject {
        guard let rawSchema = payload.metadata[CladironHealthBackup.schemaKey] else {
            throw HealthBackupDecodeError.missingSyncIdentifier
        }
        guard let schema = Int(rawSchema), schema == CladironHealthBackup.schemaVersion else {
            throw HealthBackupDecodeError.unknownSchema(Int(rawSchema) ?? -1)
        }
        guard let rawID = payload.metadata[CladironHealthBackup.syncIdentifierKey],
              let id = UUID(uuidString: rawID) else {
            throw HealthBackupDecodeError.invalidSyncIdentifier
        }
        let kind = payload.metadata[CladironHealthBackup.assessmentKindKey] ?? AssessmentKind.vo2maxField.rawValue
        let assessment = HealthAssessmentPayload(
            id: id,
            date: payload.date,
            kind: kind,
            value: payload.value,
            inputWeight: 0,
            inputReps: 0,
            exerciseName: nil,
            protocolName: payload.metadata[CladironHealthBackup.assessmentProtocolKey],
            notes: nil,
            updatedAt: date(for: payload.metadata[CladironHealthBackup.syncVersionKey]) ?? payload.date,
            inputDistance: payload.metadata[CladironHealthBackup.assessmentInputDistanceKey].flatMap(Double.init),
            inputTime: payload.metadata[CladironHealthBackup.assessmentInputTimeKey].flatMap(Double.init),
            inputEndingHR: payload.metadata[CladironHealthBackup.assessmentInputEndingHRKey].flatMap(Double.init),
            inputAge: payload.metadata[CladironHealthBackup.assessmentInputAgeKey].flatMap(Int.init),
            inputSex: payload.metadata[CladironHealthBackup.assessmentInputSexKey].flatMap(Int.init))
        return .assessment(payload: assessment, healthObjectID: payload.healthObjectID,
                           source: payload.source)
    }

    private static func decodeOwnerSets(_ raw: String?) throws -> [CladironHealthBackup.SetPayload] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        guard let sets = try? JSONDecoder().decode([CladironHealthBackup.SetPayload].self, from: data) else {
            throw HealthBackupDecodeError.invalidOwnerSets
        }
        return sets
    }

    private static func date(for raw: String?) -> Date? {
        guard let raw, let milliseconds = Int64(raw) else { return nil }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static func average(_ samples: [HRSamplePoint]) -> Double? {
        let values = samples.map(\.bpm).filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func cardioType(for kind: ImportedWorkoutKind) -> CardioType {
        switch kind {
        case .running: return .run
        case .walking: return .walk
        case .cycling: return .cycle
        case .swimming: return .swim
        case .rowing: return .rowing
        case .hiit: return .hiit
        case .boxing: return .boxing
        case .traditionalStrength, .functionalStrength, .other: return .other
        }
    }
}

public struct HealthRestoreLocalState: Codable, Equatable, Sendable {
    public let kind: HealthBackupEntityKind
    public let id: UUID
    public let updatedAt: Date
    public let healthObjectID: UUID?
    public let isDeleted: Bool

    public init(kind: HealthBackupEntityKind, id: UUID, updatedAt: Date,
                healthObjectID: UUID? = nil, isDeleted: Bool = false) {
        self.kind = kind
        self.id = id
        self.updatedAt = updatedAt
        self.healthObjectID = healthObjectID
        self.isDeleted = isDeleted
    }
}

public enum HealthRestoreAction: String, Codable, Equatable, Sendable {
    case insert
    case replace
    case skip
    case summaryOnly
}

public struct HealthRestoreOperation: Codable, Equatable, Sendable {
    public let object: HealthBackupReadObject
    public let action: HealthRestoreAction

    public init(object: HealthBackupReadObject, action: HealthRestoreAction) {
        self.object = object
        self.action = action
    }
}

public struct HealthRestorePlan: Codable, Equatable, Sendable {
    public let operations: [HealthRestoreOperation]

    public init(operations: [HealthRestoreOperation]) {
        self.operations = operations
    }

    public var inserts: Int { operations.filter { $0.action == .insert }.count }
    public var replacements: Int { operations.filter { $0.action == .replace }.count }
    public var skipped: Int { operations.filter { $0.action == .skip }.count }
    public var summariesOnly: Int { operations.filter { $0.action == .summaryOnly }.count }
}

public struct HealthRestoreApplyReport: Equatable, Sendable {
    public let inserted: Int
    public let replaced: Int
    public let skipped: Int
    public let summariesOnly: Int

    public init(inserted: Int = 0, replaced: Int = 0,
                skipped: Int = 0, summariesOnly: Int = 0) {
        self.inserted = inserted
        self.replaced = replaced
        self.skipped = skipped
        self.summariesOnly = summariesOnly
    }
}

/// Pure conflict policy for Health restore. Newer local edits always win;
/// Health may replace only an older local row. Duplicate copies from the
/// phone and Watch collapse to the highest sync version before planning.
public enum HealthBackupRestorePlanner {
    public static func plan(incoming: [HealthBackupReadObject],
                            local: [HealthRestoreLocalState]) -> HealthRestorePlan {
        var newest: [String: HealthBackupReadObject] = [:]
        for object in incoming {
            let key = "\(object.entityKind.rawValue):\(object.entityID.uuidString)"
            guard let existing = newest[key] else {
                newest[key] = object
                continue
            }
            if object.updatedAt > existing.updatedAt
                || (object.updatedAt == existing.updatedAt
                    && object.healthObjectID.uuidString < existing.healthObjectID.uuidString) {
                newest[key] = object
            }
        }

        let localByID = Dictionary(local.map { ("\($0.kind.rawValue):\($0.id.uuidString)", $0) },
                                   uniquingKeysWith: { first, _ in first })
        let localByHealthID = Dictionary(local.compactMap { state in
            state.healthObjectID.map { ($0.uuidString, state) }
        }, uniquingKeysWith: { first, _ in first })

        let operations = newest.values.sorted { $0.updatedAt < $1.updatedAt }.map { object in
            let key = "\(object.entityKind.rawValue):\(object.entityID.uuidString)"
            let existingByID = localByID[key]
            let existingByHealthID = localByHealthID[object.healthObjectID.uuidString]
            // A legacy summary has no stable Cladiron ID. Once its Health
            // object is linked locally, re-reading it must be idempotent even
            // though the synthetic local session ID is different.
            if object.isLegacy, existingByID == nil, existingByHealthID != nil {
                return HealthRestoreOperation(object: object, action: .skip)
            }
            let existing = existingByID ?? existingByHealthID
            guard let existing else {
                return HealthRestoreOperation(object: object, action: object.isLegacy ? .summaryOnly : .insert)
            }
            guard !existing.isDeleted, object.updatedAt > existing.updatedAt else {
                return HealthRestoreOperation(object: object, action: .skip)
            }
            return HealthRestoreOperation(object: object, action: .replace)
        }
        return HealthRestorePlan(operations: operations)
    }
}
