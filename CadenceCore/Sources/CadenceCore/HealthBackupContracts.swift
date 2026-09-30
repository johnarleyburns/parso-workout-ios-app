import Foundation

/// HealthKit metadata is intentionally represented as Foundation-free values in
/// CadenceCore. The iOS adapter converts these values to HealthKit's accepted
/// NSString/NSNumber/NSDate types, which keeps the backup/restore contract
/// testable on macOS and prevents HealthKit from leaking into planning code.
public enum CladironHealthBackup {
    public static let schemaVersion = 1
    public static let schemaKey = "CladironSchema"
    public static let syncIdentifierKey = "HKMetadataKeySyncIdentifier"
    public static let syncVersionKey = "HKMetadataKeySyncVersion"
    public static let setIDKey = "CladironSetID"
    public static let exerciseKey = "CladironExerciseKey"
    public static let exerciseNameKey = "CladironExerciseName"
    public static let performerKey = "CladironPerformer"
    public static let weightKgKey = "CladironWeightKg"
    public static let repsKey = "CladironReps"
    public static let rPEKey = "CladironRPE"
    public static let warmupKey = "CladironWarmup"
    public static let bodyweightKey = "CladironBodyweight"
    public static let noteKey = "CladironNote"
    public static let ownerSetsKey = "CladironOwnerSets"
    public static let titleKey = "CladironTitle"
    public static let notesKey = "CladironNotes"
    public static let hasPartnerSetsKey = "CladironHasPartnerSets"
    public static let assessmentIDKey = "CladironAssessmentID"
    public static let assessmentKindKey = "CladironAssessmentKind"
    public static let assessmentValueKey = "CladironAssessmentValue"
    public static let assessmentUnitKey = "CladironAssessmentUnit"
    public static let assessmentProtocolKey = "CladironAssessmentProtocol"
    public static let assessmentInputDistanceKey = "CladironInputDistance"
    public static let assessmentInputTimeKey = "CladironInputTime"
    public static let assessmentInputEndingHRKey = "CladironInputEndingHR"
    public static let assessmentInputWeightKey = "CladironInputWeight"
    public static let assessmentInputRepsKey = "CladironInputReps"
    public static let assessmentExerciseNameKey = "CladironAssessmentExerciseName"
    public static let assessmentNotesKey = "CladironAssessmentNotes"
    public static let assessmentInputAgeKey = "CladironInputAge"
    public static let assessmentInputSexKey = "CladironInputSex"
    public static let timingSyntheticKey = "CladironTimingSynthetic"
    public static let orderKey = "CladironOrder"
    public static let barWeightKgKey = "CladironBarWeightKg"
    public static let loadMultiplierKey = "CladironLoadMultiplier"
    public static let loadModeKey = "CladironLoadMode"

    public struct SetPayload: Codable, Equatable, Sendable {
        public let id: UUID
        public let exerciseKey: String
        public let exerciseName: String
        public let weightKg: Double
        public let reps: Int
        public let rpe: Double?
        public let isWarmup: Bool
        public let usesBodyweight: Bool
        public let note: String?
        public let order: Int
        public let completedAt: Date?
        public let barWeightKg: Double
        public let loadMultiplier: Double
        public let loadAccountingMode: String?

        public init(id: UUID, exerciseKey: String, exerciseName: String,
                    weightKg: Double, reps: Int, rpe: Double?, isWarmup: Bool,
                    usesBodyweight: Bool, note: String?, order: Int = 0,
                    completedAt: Date? = nil, barWeightKg: Double = 0,
                    loadMultiplier: Double = 1, loadAccountingMode: String? = nil) {
            self.id = id
            self.exerciseKey = exerciseKey
            self.exerciseName = exerciseName
            self.weightKg = weightKg
            self.reps = reps
            self.rpe = rpe
            self.isWarmup = isWarmup
            self.usesBodyweight = usesBodyweight
            self.note = note
            self.order = order
            self.completedAt = completedAt
            self.barWeightKg = barWeightKg
            self.loadMultiplier = loadMultiplier
            self.loadAccountingMode = loadAccountingMode
        }
    }

    public static func syncVersion(for date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    public static func baseMetadata(id: UUID, updatedAt: Date) -> [String: String] {
        [schemaKey: String(schemaVersion),
         syncIdentifierKey: id.uuidString,
         syncVersionKey: String(syncVersion(for: updatedAt))]
    }

    public static func ownerSetMetadata(for set: SetEntry,
                                        exercise: CrossStoreReferenceResolver.ExerciseReference,
                                        updatedAt: Date? = nil) -> [String: String] {
        var metadata = baseMetadata(id: set.id, updatedAt: updatedAt ?? set.updatedAt)
        metadata[setIDKey] = set.id.uuidString
        metadata[exerciseKey] = exercise.key ?? "custom:\(exercise.id?.uuidString ?? set.id.uuidString)"
        metadata[exerciseNameKey] = exercise.name
        metadata[weightKgKey] = String(set.weight)
        metadata[repsKey] = String(set.reps)
        metadata[warmupKey] = set.isWarmup ? "1" : "0"
        metadata[bodyweightKey] = set.usesBodyweight ? "1" : "0"
        if let rpe = set.rpe { metadata[rPEKey] = String(rpe) }
        if let note = set.note, !note.isEmpty { metadata[noteKey] = note }
        return metadata
    }

    public static func strengthMetadata(for session: WorkoutSession) -> [String: String] {
        let sets = session.orderedSets
        let references = CrossStoreReferenceResolver()
        let payload = sets.filter(\.isOwnerSet).map { set in
            let exercise = references.exercise(for: set, exercises: set.exercise.map { [$0] } ?? [])
            return SetPayload(id: set.id,
                              exerciseKey: exercise.key ?? "custom:\(exercise.id?.uuidString ?? set.id.uuidString)",
                              exerciseName: exercise.name,
                              weightKg: set.weight,
                              reps: set.reps,
                              rpe: set.rpe,
                              isWarmup: set.isWarmup,
                              usesBodyweight: set.usesBodyweight,
                              note: set.note,
                              order: set.order,
                              completedAt: set.completedAt,
                              barWeightKg: set.barWeightKg,
                              loadMultiplier: set.loadMultiplier,
                              loadAccountingMode: set.loadAccountingMode)
        }
        var metadata = baseMetadata(id: session.id, updatedAt: session.updatedAt)
        metadata[titleKey] = session.title
        if let notes = session.notes, !notes.isEmpty { metadata[notesKey] = notes }
        metadata[hasPartnerSetsKey] = sets.contains { !$0.isOwnerSet } ? "1" : "0"
        if let data = try? JSONEncoder().encode(payload) {
            metadata[ownerSetsKey] = String(decoding: data, as: UTF8.self)
        }
        return metadata
    }

    public static func isSupported(_ metadata: [String: String]) -> Bool {
        metadata[schemaKey].flatMap(Int.init) == schemaVersion
    }
}

/// The rows that can be represented by a Cladiron-authored HealthKit object.
/// Partner sets are deliberately absent: Health is the user's private health
/// record and must never receive another person's identity or workout details.
public enum HealthBackupEntityKind: String, Codable, CaseIterable, Sendable {
    case strengthSession
    case cardioWorkout
    case assessment
}

public enum HealthOutboxOperation: String, Codable, Sendable {
    case upsert
    case delete
}

public struct HealthAssessmentPayload: Codable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let kind: String
    public let value: Double
    public let inputWeight: Double
    public let inputReps: Int
    public let exerciseName: String?
    public let protocolName: String?
    public let notes: String?
    public let updatedAt: Date
    public let inputDistance: Double?
    public let inputTime: Double?
    public let inputEndingHR: Double?
    public let inputAge: Int?
    public let inputSex: Int?

    public init(id: UUID, date: Date, kind: String, value: Double,
                inputWeight: Double, inputReps: Int, exerciseName: String?,
                protocolName: String?, notes: String?, updatedAt: Date,
                inputDistance: Double?, inputTime: Double?, inputEndingHR: Double?,
                inputAge: Int?, inputSex: Int?) {
        self.id = id; self.date = date; self.kind = kind; self.value = value
        self.inputWeight = inputWeight; self.inputReps = inputReps
        self.exerciseName = exerciseName; self.protocolName = protocolName
        self.notes = notes; self.updatedAt = updatedAt
        self.inputDistance = inputDistance; self.inputTime = inputTime
        self.inputEndingHR = inputEndingHR; self.inputAge = inputAge
        self.inputSex = inputSex
    }
}

public enum HealthBackupJob: Codable, Equatable, Sendable {
    case strength(StrengthWorkoutSummary)
    case cardio(CardioWorkoutSummary)
    case assessment(HealthAssessmentPayload)
    case delete(kind: HealthBackupEntityKind, id: UUID, syncVersion: Int64)

    public var entityKind: HealthBackupEntityKind {
        switch self {
        case .strength: return .strengthSession
        case .cardio: return .cardioWorkout
        case .assessment: return .assessment
        case .delete(let kind, _, _): return kind
        }
    }

    public var entityID: UUID {
        switch self {
        case .strength(let value): return value.id
        case .cardio(let value): return value.id
        case .assessment(let value): return value.id
        case .delete(_, let id, _): return id
        }
    }

    public var syncVersion: Int64 {
        switch self {
        case .strength(let value): return CladironHealthBackup.syncVersion(for: value.updatedAt ?? value.end)
        case .cardio(let value): return CladironHealthBackup.syncVersion(for: value.updatedAt ?? value.end)
        case .assessment(let value): return CladironHealthBackup.syncVersion(for: value.updatedAt)
        case .delete(_, _, let version): return version
        }
    }

    public var operation: HealthOutboxOperation {
        if case .delete = self { return .delete }
        return .upsert
    }
}

/// A durable, local-only queue entry. It intentionally lives in an app-owned
/// file until H5 creates the dedicated local SwiftData configuration; putting
/// it in the current CloudKit-backed schema would leak health state to the old
/// container.
public struct HealthOutboxItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let entityKind: HealthBackupEntityKind
    public let entityID: UUID
    public var operation: HealthOutboxOperation
    public var syncVersion: Int64
    public var payload: Data?
    public var attemptCount: Int
    public var nextAttemptAt: Date
    public var lastAttemptAt: Date?
    public var lastError: String?
    public let enqueuedAt: Date

    public init(id: UUID = UUID(), entityKind: HealthBackupEntityKind,
                entityID: UUID, operation: HealthOutboxOperation,
                syncVersion: Int64, payload: Data? = nil,
                attemptCount: Int = 0, nextAttemptAt: Date = Date(),
                lastAttemptAt: Date? = nil, lastError: String? = nil,
                enqueuedAt: Date = Date()) {
        self.id = id; self.entityKind = entityKind; self.entityID = entityID
        self.operation = operation; self.syncVersion = syncVersion
        self.payload = payload; self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt; self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError; self.enqueuedAt = enqueuedAt
    }

    public init(job: HealthBackupJob, now: Date = Date()) throws {
        self.init(entityKind: job.entityKind, entityID: job.entityID,
                  operation: job.operation, syncVersion: job.syncVersion,
                  payload: try JSONEncoder().encode(job), now: now)
    }

    private init(entityKind: HealthBackupEntityKind, entityID: UUID,
                 operation: HealthOutboxOperation, syncVersion: Int64,
                 payload: Data?, now: Date) {
        self.init(entityKind: entityKind, entityID: entityID, operation: operation,
                  syncVersion: syncVersion, payload: payload,
                  nextAttemptAt: now, enqueuedAt: now)
    }

    public func decodeJob() throws -> HealthBackupJob {
        guard let payload else {
            throw HealthOutboxError.missingPayload
        }
        return try JSONDecoder().decode(HealthBackupJob.self, from: payload)
    }
}

public enum HealthOutboxError: Error, Equatable, Sendable {
    case missingPayload
    case corruptFile
}

/// Pure state machine for enqueue/coalesce/retry behavior. This is separate
/// from file I/O so every failure mode can be tested without HealthKit.
public struct HealthOutboxQueue: Codable, Equatable, Sendable {
    public private(set) var items: [HealthOutboxItem]

    public init(items: [HealthOutboxItem] = []) { self.items = items }

    public mutating func enqueue(_ item: HealthOutboxItem) {
        guard let index = items.firstIndex(where: {
            $0.entityKind == item.entityKind && $0.entityID == item.entityID
        }) else {
            items.append(item)
            return
        }

        let existing = items[index]
        // A create/edit followed by a delete before the first attempt never
        // needs to touch Health. Once the object was attempted, retain a delete
        // tombstone so a previously saved Health object is removed.
        if item.operation == .delete,
           existing.operation == .upsert,
           existing.attemptCount == 0 {
            items.remove(at: index)
            return
        }
        guard item.syncVersion >= existing.syncVersion || item.operation == .delete else { return }
        var replacement = item
        replacement.attemptCount = 0
        replacement.lastAttemptAt = nil
        replacement.lastError = nil
        items[index] = replacement
    }

    public func due(at now: Date = Date()) -> [HealthOutboxItem] {
        items.filter { $0.nextAttemptAt <= now }
            .sorted { $0.enqueuedAt < $1.enqueuedAt }
    }

    public mutating func markSucceeded(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    public mutating func markFailed(_ id: UUID, error: String, at now: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].attemptCount += 1
        items[index].lastAttemptAt = now
        items[index].lastError = error
        let delay = Self.retryDelaySeconds(forAttempt: items[index].attemptCount)
        items[index].nextAttemptAt = now.addingTimeInterval(delay)
    }

    public static func retryDelaySeconds(forAttempt attempt: Int) -> TimeInterval {
        let exponent = max(0, min(attempt - 1, 9))
        return min(1_800, 5 * pow(2, Double(exponent)))
    }
}

/// Actor-isolated JSON persistence for the outbox. Writes are atomic and the
/// directory is created lazily, so a locked/offline device can retain work
/// without depending on SwiftData or CloudKit availability.
public actor HealthOutboxStore {
    private let fileURL: URL
    private var queue: HealthOutboxQueue?

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func snapshot() throws -> HealthOutboxQueue {
        try loadIfNeeded()
        return queue ?? HealthOutboxQueue()
    }

    public func enqueue(_ item: HealthOutboxItem) throws {
        try loadIfNeeded()
        var value = queue ?? HealthOutboxQueue()
        value.enqueue(item)
        queue = value
        try persist()
    }

    public func due(at now: Date = Date()) throws -> [HealthOutboxItem] {
        try snapshot().due(at: now)
    }

    public func markSucceeded(_ id: UUID) throws {
        try loadIfNeeded()
        queue?.markSucceeded(id)
        try persist()
    }

    public func markFailed(_ id: UUID, error: String, at now: Date = Date()) throws {
        try loadIfNeeded()
        queue?.markFailed(id, error: error, at: now)
        try persist()
    }

    private func loadIfNeeded() throws {
        guard queue == nil else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            queue = HealthOutboxQueue()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            queue = try JSONDecoder().decode(HealthOutboxQueue.self, from: data)
        } catch {
            throw HealthOutboxError.corruptFile
        }
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(queue ?? HealthOutboxQueue())
        try data.write(to: fileURL, options: .atomic)
    }
}

/// Converts persisted rows into HealthKit-safe jobs without importing
/// HealthKit. The app adapter can use these summaries directly or encode the
/// same metadata into workout activities.
public enum HealthBackupEncoder {
    public static func strengthSummary(for session: WorkoutSession,
                                       activeEnergyKcal: Double? = nil,
                                       hrSamples: [HRSamplePoint] = []) -> StrengthWorkoutSummary? {
        let sets = session.orderedSets
        guard let first = sets.compactMap(\.completedAt).min() else { return nil }
        let last = sets.compactMap(\.completedAt).max() ?? first
        let end = max(last, first.addingTimeInterval(60))
        let bpm = hrSamples.map(\.bpm).filter { $0 > 0 }
        return StrengthWorkoutSummary(
            id: session.id, start: first, end: end,
            activeEnergyKcal: activeEnergyKcal,
            hrSamples: hrSamples,
            avgHR: bpm.isEmpty ? nil : bpm.reduce(0, +) / Double(bpm.count),
            maxHR: bpm.max(),
            metadata: CladironHealthBackup.strengthMetadata(for: session),
            updatedAt: session.updatedAt)
    }

    public static func cardioSummary(for cardio: CardioWorkout) -> CardioWorkoutSummary {
        let samples = cardio.orderedHRSamples.map { HRSamplePoint(t: $0.t, bpm: $0.bpm) }
        let route = cardio.orderedRouteSamples.map {
            LocationFix(t: $0.t, lat: $0.lat, lon: $0.lon,
                        elevation: $0.elevation)
        }
        return CardioWorkoutSummary(
            id: cardio.id, type: cardio.typeValue, start: cardio.start,
            end: cardio.end ?? cardio.start, distanceMeters: cardio.distance,
            activeEnergyKcal: cardio.activeEnergy, hrSamples: samples, route: route,
            intervalSummary: cardio.intervalSummary, customTitle: cardio.customTitle,
            isLogged: cardio.isLogged, targetDistanceMeters: cardio.targetDistance,
            intensityProfile: cardio.intensityProfile, intensitySummary: cardio.intensitySummary,
            metEstimate: cardio.standardMETValue.map {
                METEstimate(standardMET: $0, metMinutes: cardio.standardMETMinutes,
                            activeMinutes: cardio.duration / 60,
                            method: cardio.metMethodRaw.flatMap(METEstimationMethod.init(rawValue:)) ?? .unavailable,
                            basis: cardio.metBasisRaw.flatMap(METBasis.init(rawValue:)) ?? .standardCompendium,
                            confidence: .estimated, sourceCitationIDs: [])
            }, updatedAt: cardio.updatedAt)
    }

    public static func assessmentPayload(for assessment: Assessment) -> HealthAssessmentPayload {
        HealthAssessmentPayload(id: assessment.id, date: assessment.date,
                                kind: assessment.kind, value: assessment.value,
                                inputWeight: assessment.inputWeight, inputReps: assessment.inputReps,
                                exerciseName: assessment.exerciseName,
                                protocolName: assessment.protocolName, notes: assessment.notes,
                                updatedAt: assessment.updatedAt,
                                inputDistance: assessment.inputDistance,
                                inputTime: assessment.inputTime,
                                inputEndingHR: assessment.inputEndingHR,
                                inputAge: assessment.inputAge, inputSex: assessment.inputSex)
    }
}

public struct HealthRestoreVersion: Equatable, Sendable {
    public let updatedAt: Date
    public let deletedAt: Date?

    public init(updatedAt: Date, deletedAt: Date? = nil) {
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public enum HealthRestoreDecision: Equatable, Sendable {
    case insert
    case replaceLocal
    case keepLocal
    case applyTombstone
}

/// Pure last-writer-wins policy used by both the Health reader and future
/// CloudKit migration runner. Equal versions keep local data so an export/import
/// cannot unexpectedly replace an edit made on this device.
public enum HealthRestorePlanner {
    public static func decision(local: HealthRestoreVersion?, incoming: HealthRestoreVersion) -> HealthRestoreDecision {
        guard let local else {
            return incoming.deletedAt == nil ? .insert : .keepLocal
        }
        guard incoming.updatedAt > local.updatedAt else { return .keepLocal }
        return incoming.deletedAt == nil ? .replaceLocal : .applyTombstone
    }
}
