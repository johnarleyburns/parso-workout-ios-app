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

        public init(id: UUID, exerciseKey: String, exerciseName: String,
                    weightKg: Double, reps: Int, rpe: Double?, isWarmup: Bool,
                    usesBodyweight: Bool, note: String?) {
            self.id = id
            self.exerciseKey = exerciseKey
            self.exerciseName = exerciseName
            self.weightKg = weightKg
            self.reps = reps
            self.rpe = rpe
            self.isWarmup = isWarmup
            self.usesBodyweight = usesBodyweight
            self.note = note
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
                              note: set.note)
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
