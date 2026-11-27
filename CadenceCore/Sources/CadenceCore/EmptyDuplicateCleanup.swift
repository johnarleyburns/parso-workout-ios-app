#if canImport(SwiftData)
import Foundation
import SwiftData

/// One-time cleanup for the 1184 recovery aftermath. Restoring from Apple Health
/// created a duration-only session for a workout that could not be matched to
/// its local row, so History showed two entries for the same workout: the real
/// one with sets and an empty twin.
///
/// This only *soft-deletes* an empty session when a session with sets exists
/// within fifteen minutes of it. Nothing is destroyed, nothing is merged, and
/// the run is recorded with a marker so it never repeats.
public enum EmptyDuplicateCleanup {
    public static let markerFileName = "empty-duplicate-cleanup.complete.json"
    /// Two records of the same workout can drift by a few minutes while a
    /// Watch session finalises; anything further apart is a different workout.
    public static let matchWindow: TimeInterval = 15 * 60

    public struct Report: Sendable, Equatable {
        public let hidden: Int
        public let kept: Int
        public init(hidden: Int, kept: Int) { self.hidden = hidden; self.kept = kept }
    }

    public struct Session: Sendable, Equatable {
        public let id: UUID
        public let date: Date
        public let hasSets: Bool
        public let isDeleted: Bool
        public init(id: UUID, date: Date, hasSets: Bool, isDeleted: Bool) {
            self.id = id
            self.date = date
            self.hasSets = hasSets
            self.isDeleted = isDeleted
        }
    }

    /// Pure selection so the predicate is testable without a store.
    public static func duplicateIDs(in sessions: [Session],
                                    window: TimeInterval = matchWindow) -> [UUID] {
        let live = sessions.filter { !$0.isDeleted }
        let withSets = live.filter(\.hasSets).map(\.date)
        guard !withSets.isEmpty else { return [] }
        return live
            .filter { !$0.hasSets }
            .filter { empty in withSets.contains { abs($0.timeIntervalSince(empty.date)) < window } }
            .map(\.id)
    }

    /// Runs once per install. Returns `nil` when it has already run or when the
    /// container is in-memory.
    public static func runIfNeeded(container: ModelContainer,
                                   directory: URL = CadenceStore.applicationSupportDirectory(),
                                   fileManager: FileManager = .default) -> Report? {
        guard container.configurations.contains(where: { !$0.isStoredInMemoryOnly }) else { return nil }
        let marker = directory.appendingPathComponent(markerFileName)
        guard !fileManager.fileExists(atPath: marker.path) else { return nil }

        let context = ModelContext(container)
        guard let sessions = try? context.fetch(FetchDescriptor<WorkoutSession>()) else { return nil }
        let snapshots = sessions.map {
            Session(id: $0.id, date: $0.date,
                    hasSets: !$0.orderedSets.isEmpty,
                    isDeleted: $0.deletedAt != nil)
        }
        let duplicates = Set(duplicateIDs(in: snapshots))
        guard !duplicates.isEmpty else {
            try? Data("clean\n".utf8).write(to: marker, options: .atomic)
            return Report(hidden: 0, kept: snapshots.filter { !$0.isDeleted && $0.hasSets }.count)
        }

        let now = Date()
        var hidden = 0
        for session in sessions where duplicates.contains(session.id) {
            session.deletedAt = now
            hidden += 1
        }
        guard (try? context.save()) != nil else { return nil }
        try? Data("clean\n".utf8).write(to: marker, options: .atomic)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("cadence.workoutHistoryChanged"),
                                            object: nil)
        }
        return Report(hidden: hidden,
                      kept: snapshots.filter { !$0.isDeleted && $0.hasSets }.count)
    }
}
#endif
