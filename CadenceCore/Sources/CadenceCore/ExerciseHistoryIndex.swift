import Foundation
import CryptoKit

/// The small, app-local projection used by Personalized suggestions. This is
/// deliberately not a SwiftData `@Model`: the canonical workout models remain
/// the only CloudKit records, and this derived cache can always be recreated.
/// That keeps the index iOS 17 compatible and avoids a CloudKit schema change.
public struct ExerciseHistoryIndexEntry: Codable, Equatable, Sendable {
    public let exerciseKey: String
    public let exerciseName: String
    public let firstCompletedAt: Date
    public let lastCompletedAt: Date
    public let completedWorkoutCount: Int
    public let completedWorkingSetCount: Int

    public init(exerciseKey: String, exerciseName: String,
                firstCompletedAt: Date, lastCompletedAt: Date,
                completedWorkoutCount: Int, completedWorkingSetCount: Int) {
        self.exerciseKey = exerciseKey
        self.exerciseName = exerciseName
        self.firstCompletedAt = firstCompletedAt
        self.lastCompletedAt = lastCompletedAt
        self.completedWorkoutCount = completedWorkoutCount
        self.completedWorkingSetCount = completedWorkingSetCount
    }
}

public struct ExerciseHistoryIndexSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let sourceSignature: String
    public let rebuiltAt: Date
    public let entries: [String: ExerciseHistoryIndexEntry]

    public init(version: Int = Self.currentVersion, sourceSignature: String,
                rebuiltAt: Date = Date(),
                entries: [String: ExerciseHistoryIndexEntry]) {
        self.version = version
        self.sourceSignature = sourceSignature
        self.rebuiltAt = rebuiltAt
        self.entries = entries
    }
}

private final class ExerciseHistoryIndexSignatureCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func contains(_ signature: String, for key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return values[key] == signature
    }

    func set(_ signature: String, for key: String) {
        lock.lock()
        values[key] = signature
        lock.unlock()
    }
}

/// Builds and persists the derived historical-exercise projection. Callers pass
/// only sessions that are eligible for the current user's history; in production
/// that excludes the active session so a half-entered workout cannot personalize
/// its own suggestion.
public enum ExerciseHistoryIndexStore {
    public static let fileName = "exercise-history-index.json"
    private static let signatureCache = ExerciseHistoryIndexSignatureCache()

    /// Returns the app-support location used by the iPhone. A nil URL means an
    /// in-memory index, which is used by tests and isolated UI-test stores.
    public static func defaultStorageURL() -> URL? {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first else { return nil }
        let directory = root.appendingPathComponent("ExerciseHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    /// Rebuilds the projection when the canonical history has changed. The
    /// signature includes every relevant session/set identity and classification,
    /// so edits and deletions cannot leave stale exercise keys behind.
    @discardableResult
    public static func rebuildIfNeeded(sessions: [WorkoutSession],
                                       excludingSessionIDs: Set<UUID> = [],
                                       storageURL: URL? = defaultStorageURL()) throws -> Bool {
        let signature = sourceSignature(for: sessions, excludingSessionIDs: excludingSessionIDs)
        let cacheKey = storageURL?.standardizedFileURL.path ?? "memory"
        // Avoid a second rebuild in the same process when the filesystem has
        // not yet surfaced the just-written snapshot to a concurrent reader.
        // The key is still the complete content signature, so any workout/set
        // edit or deletion invalidates this fast path.
        if signatureCache.contains(signature, for: cacheKey) { return false }
        if let existing = try load(from: storageURL),
           existing.version == ExerciseHistoryIndexSnapshot.currentVersion,
           existing.sourceSignature == signature {
            signatureCache.set(signature, for: cacheKey)
            return false
        }

        let snapshot = build(sessions: sessions, excludingSessionIDs: excludingSessionIDs,
                             sourceSignature: signature)
        try save(snapshot, to: storageURL)
        signatureCache.set(signature, for: cacheKey)
        return true
    }

    /// Returns the complete set of stable keys observed in all eligible history.
    /// The first call performs the unbounded backfill, including old workouts;
    /// later calls read only the compact projection.
    public static func personalizedExerciseKeys(sessions: [WorkoutSession],
                                                excludingSessionIDs: Set<UUID> = [],
                                                storageURL: URL? = defaultStorageURL()) throws -> Set<String> {
        // A nil URL is the intentional in-memory mode used by isolated tests
        // and UI-test stores. It must still return the freshly built projection;
        // there is simply no disk snapshot to reload afterward.
        guard storageURL != nil else {
            let signature = sourceSignature(for: sessions,
                                            excludingSessionIDs: excludingSessionIDs)
            return Set(build(sessions: sessions,
                             excludingSessionIDs: excludingSessionIDs,
                             sourceSignature: signature).entries.keys)
        }
        try rebuildIfNeeded(sessions: sessions,
                            excludingSessionIDs: excludingSessionIDs,
                            storageURL: storageURL)
        return Set((try load(from: storageURL).map { Array($0.entries.keys) }) ?? [])
    }

    /// Exposed for tests and diagnostics. The builder is deterministic and does
    /// not depend on fetch ordering or a recency limit.
    public static func build(sessions: [WorkoutSession],
                             excludingSessionIDs: Set<UUID> = [],
                             sourceSignature: String? = nil,
                             rebuiltAt: Date = Date()) -> ExerciseHistoryIndexSnapshot {
        struct MutableEntry {
            var name: String
            var first: Date
            var last: Date
            var workoutIDs = Set<UUID>()
            var setCount = 0
        }

        var aggregate: [String: MutableEntry] = [:]
        for session in sessions where !excludingSessionIDs.contains(session.id)
            && session.countsAsStrengthHistory {
            for set in session.orderedSets where !set.isWarmup
                && set.isOwnerSet && set.reps > 0 {
                guard let exercise = set.exercise else { continue }
                let aliases = [
                    ExerciseSuggestionExclusionKey.forExercise(exercise),
                    "legacy:\(ExerciseLibrary.dedupKey(exercise.name))"
                ]
                for key in Set(aliases) where !key.isEmpty {
                    if var entry = aggregate[key] {
                        entry.first = min(entry.first, set.completedAt)
                        entry.last = max(entry.last, set.completedAt)
                        entry.workoutIDs.insert(session.id)
                        entry.setCount += 1
                        aggregate[key] = entry
                    } else {
                        aggregate[key] = MutableEntry(name: exercise.name,
                                                      first: set.completedAt,
                                                      last: set.completedAt,
                                                      workoutIDs: [session.id],
                                                      setCount: 1)
                    }
                }
            }
        }

        var keyedEntries: [String: ExerciseHistoryIndexEntry] = [:]
        for (key, value) in aggregate {
            keyedEntries[key] = ExerciseHistoryIndexEntry(
                exerciseKey: key,
                exerciseName: value.name,
                firstCompletedAt: value.first,
                lastCompletedAt: value.last,
                completedWorkoutCount: value.workoutIDs.count,
                completedWorkingSetCount: value.setCount)
        }
        return ExerciseHistoryIndexSnapshot(
            sourceSignature: sourceSignature ?? Self.sourceSignature(
                for: sessions, excludingSessionIDs: excludingSessionIDs),
            rebuiltAt: rebuiltAt,
            entries: keyedEntries)
    }

    public static func sourceSignature(for sessions: [WorkoutSession],
                                       excludingSessionIDs: Set<UUID> = []) -> String {
        struct SetStamp: Codable {
            let id: String
            let completedAtMilliseconds: Int64
            let reps: Int
            let isWarmup: Bool
            let isOwner: Bool
            let exerciseKey: String
        }
        struct SessionStamp: Codable {
            let id: String
            let isEnded: Bool
            let isDeleted: Bool
            let isLogged: Bool
            let sets: [SetStamp]
        }

        let stamps = sessions
            .filter { !excludingSessionIDs.contains($0.id) }
            .map { session in
                SessionStamp(
                    id: session.id.uuidString,
                    isEnded: session.endedAt != nil,
                    isDeleted: session.deletedAt != nil,
                    isLogged: session.isLogged,
                    sets: session.orderedSets.map { set in
                        SetStamp(
                            id: set.id.uuidString,
                            completedAtMilliseconds: Int64(
                                (set.completedAt.timeIntervalSince1970 * 1_000).rounded()),
                            reps: set.reps,
                            isWarmup: set.isWarmup,
                            isOwner: set.isOwnerSet,
                            exerciseKey: set.exercise.map(ExerciseSuggestionExclusionKey.forExercise) ?? "")
                    }.sorted { $0.id < $1.id })
            }
            .sorted { $0.id < $1.id }
        guard let data = try? JSONEncoder().encode(stamps) else { return "unavailable" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func load(from url: URL?) throws -> ExerciseHistoryIndexSnapshot? {
        guard let url else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ExerciseHistoryIndexSnapshot.self, from: data)
    }

    private static func save(_ snapshot: ExerciseHistoryIndexSnapshot, to url: URL?) throws {
        guard let url else { return }
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
