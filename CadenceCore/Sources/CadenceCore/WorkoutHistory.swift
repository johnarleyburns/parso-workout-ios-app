import Foundation
import SwiftData

/// A single entry in the unified (strength + cardio) workout history
/// (field-testing Round 4 A4). Wraps the underlying `@Model` row so the list
/// can render either kind; `id`/`date` give a stable identity and sort key.
public enum WorkoutHistoryEntry: Identifiable, Sendable {
    case strength(WorkoutSession)
    case cardio(CardioWorkout)

    public var id: UUID {
        switch self {
        case .strength(let s): return s.id
        case .cardio(let c): return c.id
        }
    }

    /// The moment the workout occurred — `session.date` / `cardio.start`.
    /// Used to merge-sort both kinds newest-first.
    public var date: Date {
        switch self {
        case .strength(let s): return s.date
        case .cardio(let c): return c.start
        }
    }
}

extension WorkoutRepository {
    /// All strength sessions + cardio workouts, merged and sorted newest-first
    /// by `date`/`start` (field-testing Round 4 A4). An empty store returns `[]`.
    public static func unifiedHistory(_ context: ModelContext) throws -> [WorkoutHistoryEntry] {
        let strength = try allSessions(context).map(WorkoutHistoryEntry.strength)
        let cardio = try allCardio(context).map(WorkoutHistoryEntry.cardio)
        return (strength + cardio).sorted { $0.date > $1.date }
    }
}
