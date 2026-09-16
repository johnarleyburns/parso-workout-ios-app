import Foundation
import SwiftData

/// A personal preference that affects only automatically generated suggestions.
/// This deliberately does not live on `Exercise`: catalog facts are shared and
/// refreshed, while exclusions belong to one user's private store.
@Model
public final class ExerciseSuggestionExclusion {
    public var id: UUID = UUID()
    /// Namespaced stable key: `dbpp:<source id>`, `custom:<UUID>`, or
    /// `legacy:<normalized name>`.
    public var exerciseKey: String = ""
    /// Keeps the Settings list understandable if catalog metadata changes.
    public var exerciseNameSnapshot: String = ""
    public var reasonRaw: String = ExerciseSuggestionExclusionReason.personalPreference.rawValue
    /// Kept as a tombstone instead of deleting the row so a stale CloudKit
    /// device cannot resurrect an old exclusion after the user re-enables it.
    public var isActive: Bool = true
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var originDevice: String = ""

    public init(id: UUID = UUID(), exerciseKey: String = "",
                exerciseNameSnapshot: String = "",
                reason: ExerciseSuggestionExclusionReason = .personalPreference,
                isActive: Bool = true, createdAt: Date = Date(),
                updatedAt: Date = Date(), originDevice: String = "") {
        self.id = id
        self.exerciseKey = exerciseKey
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.reasonRaw = reason.rawValue
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originDevice = originDevice
    }

    public var reason: ExerciseSuggestionExclusionReason {
        get { ExerciseSuggestionExclusionReason(rawValue: reasonRaw) ?? .personalPreference }
        set { reasonRaw = newValue.rawValue }
    }
}

public enum ExerciseSuggestionExclusionReason: String, CaseIterable, Codable, Identifiable, Sendable {
    case notAtGym
    case injuryOrHealth
    case personalPreference
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .notAtGym: "Not available at my gym"
        case .injuryOrHealth: "Injury or health concern"
        case .personalPreference: "Personal preference"
        case .other: "Other"
        }
    }
}

/// Converts catalog identity into a key that survives catalog refreshes and
/// also gives legacy, source-less rows a deterministic fallback.
public enum ExerciseSuggestionExclusionKey {
    public static func forExercise(_ exercise: Exercise) -> String {
        if let source = exercise.sourceExerciseID, !source.isEmpty {
            return "dbpp:\(source)"
        }
        if exercise.isCustom {
            return "custom:\(exercise.id.uuidString.lowercased())"
        }
        return "legacy:\(ExerciseLibrary.dedupKey(exercise.name))"
    }

    public static func forTemplate(_ template: ExerciseTemplate) -> String {
        if let source = template.sourceExerciseID, !source.isEmpty {
            return "dbpp:\(source)"
        }
        return "legacy:\(ExerciseLibrary.dedupKey(template.name))"
    }

    /// Candidate IDs from older pure-generator callers were un-namespaced. The
    /// aliases keep those callers filterable while production candidates use
    /// the stable namespaced key above.
    public static func matches(_ exclusionKey: String, candidateID: String) -> Bool {
        guard !exclusionKey.isEmpty, !candidateID.isEmpty else { return false }
        if exclusionKey == candidateID { return true }
        return exclusionKey == "dbpp:\(candidateID)"
            || exclusionKey == "custom:\(candidateID.lowercased())"
            || exclusionKey == "legacy:\(ExerciseLibrary.dedupKey(candidateID))"
    }
}

public enum ExerciseSuggestionExclusionStore {
    public static func active(in context: ModelContext) throws -> [ExerciseSuggestionExclusion] {
        try context.fetch(FetchDescriptor<ExerciseSuggestionExclusion>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\ExerciseSuggestionExclusion.exerciseNameSnapshot)]))
    }

    public static func activeKeys(in context: ModelContext) throws -> Set<String> {
        Set(try active(in: context).map(\ExerciseSuggestionExclusion.exerciseKey))
    }

    @discardableResult
    public static func setExcluded(exercise: Exercise,
                                   reason: ExerciseSuggestionExclusionReason,
                                   originDevice: String = "iphone",
                                   in context: ModelContext) throws -> ExerciseSuggestionExclusion {
        try setExcluded(key: ExerciseSuggestionExclusionKey.forExercise(exercise),
                        name: exercise.name, reason: reason,
                        originDevice: originDevice, in: context)
    }

    @discardableResult
    public static func setExcluded(key: String, name: String,
                                   reason: ExerciseSuggestionExclusionReason,
                                   originDevice: String = "iphone",
                                   in context: ModelContext) throws -> ExerciseSuggestionExclusion {
        let records = try context.fetch(FetchDescriptor<ExerciseSuggestionExclusion>(
            predicate: #Predicate { $0.exerciseKey == key },
            sortBy: [SortDescriptor(\ExerciseSuggestionExclusion.updatedAt, order: .reverse)]))
        let record = records.first ?? ExerciseSuggestionExclusion(exerciseKey: key,
                                                                    exerciseNameSnapshot: name,
                                                                    reason: reason,
                                                                    originDevice: originDevice)
        if records.isEmpty { context.insert(record) }
        record.exerciseNameSnapshot = name
        record.reason = reason
        record.isActive = true
        record.updatedAt = Date()
        record.originDevice = originDevice
        try context.save()
        return record
    }

    public static func allow(_ record: ExerciseSuggestionExclusion,
                             originDevice: String = "iphone",
                             in context: ModelContext) throws {
        record.isActive = false
        record.updatedAt = Date()
        record.originDevice = originDevice
        try context.save()
    }
}

public enum SuggestedExerciseFilter {
    public static func excluding(_ candidates: [SuggestedExerciseCandidate],
                                 keys: Set<String>) -> [SuggestedExerciseCandidate] {
        candidates.filter { candidate in
            !keys.contains { ExerciseSuggestionExclusionKey.matches($0, candidateID: candidate.id) }
        }
    }
}
