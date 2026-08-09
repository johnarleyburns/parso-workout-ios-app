import Foundation
import SwiftData

/// A single entry in the unified (strength + cardio) workout history
/// (field-testing Round 4 A4). Wraps the underlying `@Model` row so the list
/// can render either kind; `id`/`date` give a stable identity and sort key.
public enum WorkoutHistoryEntry: Identifiable {
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

    /// Ranks past strength sessions by how many of the `missing` body parts they
    /// cover (feedback batch 8 — Home "body parts" quick-start). A session's coverage
    /// is the union of its logged exercises' body parts intersected with `missing`.
    /// Returns only sessions covering ≥1 missing part, most-covered first, ties
    /// broken by recency. `sessions` is assumed newest-first (as from `allSessions`).
    public static func workoutsByMissingCoverage(_ sessions: [WorkoutSession],
                                                 missing: [BodyPart])
        -> [(session: WorkoutSession, covered: [BodyPart])] {
        guard !missing.isEmpty else { return [] }
        let want = Set(missing)
        let ranked: [(WorkoutSession, [BodyPart])] = sessions.compactMap { s in
            var hit = Set<BodyPart>()
            for ex in s.exercisesInOrder { hit.formUnion(BodyPart.parts(forMuscleIDs: ex.muscleGroups)) }
            let covered = want.intersection(hit)
            guard !covered.isEmpty else { return nil }
            // Stable display order for the covered chips.
            return (s, BodyPart.allCases.filter { covered.contains($0) })
        }
        // `sessions` is already newest-first, so a stable sort by covered-count desc
        // keeps recency as the tie-breaker.
        return ranked
            .enumerated()
            .sorted { a, b in
                a.element.1.count != b.element.1.count
                    ? a.element.1.count > b.element.1.count
                    : a.offset < b.offset
            }
            .map { ($0.element.0, $0.element.1) }
    }
}
