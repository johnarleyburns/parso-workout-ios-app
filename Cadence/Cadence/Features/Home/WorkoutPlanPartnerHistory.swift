import Foundation
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Gathers one performer's logged history for one movement so
/// `PartnerPlanResolver` (pure, in `CadenceFeatures`) can fill their plan.
/// Lives in the app target because it reads `@Model` rows; it holds no policy —
/// every "what should this partner do" decision stays in the resolver.
enum WorkoutPlanPartnerHistory {

    /// A bounded snapshot for one plan-editor presentation. The previous
    /// implementation refetched all exercises and all sessions once per
    /// exercise/partner pair, which made an otherwise local plan screen stall
    /// for seconds on larger histories.
    struct Index {
        private let exercisesByName: [String: [Exercise]]
        private let exercisesByKey: [String: [Exercise]]
        private let sessions: [WorkoutSession]

        init(context: ModelContext) {
            let exercises = (try? WorkoutRepository.allExercises(context)) ?? []
            exercisesByName = Dictionary(grouping: exercises) {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            exercisesByKey = Dictionary(grouping: exercises) { ExerciseLibrary.dedupKey($0.name) }
            sessions = (try? WorkoutRepository.allSessions(context)) ?? []
        }

        func history(forExerciseNamed name: String,
                     performerID: UUID?,
                     people: [Person]) -> PartnerPlanResolver.ExerciseHistory {
            let general = generalRepLadders(performerID: performerID)
            if let performerID,
               !people.contains(where: { $0.id == performerID }) {
                // Unknown partner: never fall through to the owner's history.
                return PartnerPlanResolver.ExerciseHistory(generalRepLadders: general)
            }
            let rows = matchingExercises(named: name)
            guard !rows.isEmpty else {
                // No history for this movement: leave loads blank. The old
                // cross-exercise "most recent weight" guess made every new
                // exercise inherit the same number.
                return PartnerPlanResolver.ExerciseHistory(generalRepLadders: general)
            }
            // Duplicate/custom rows can split one movement's history. Merge all
            // matching rows so a plan never misses the row that actually has sets.
            let sets = rows.flatMap { $0.sets ?? [] }
                .filter { matches($0, performerID: performerID) }
                .sorted { $0.completedAt < $1.completedAt }
            let working = sets.filter { !$0.isWarmup && $0.reps > 0 }
            let bySession = Dictionary(grouping: working) { $0.session?.id ?? UUID() }
            let sessionsOldestFirst = bySession.values.sorted { sessionDate($0) < sessionDate($1) }
            let last = (sessionsOldestFirst.last ?? []).sorted { $0.order < $1.order }
            return PartnerPlanResolver.ExerciseHistory(
                lastSets: last.map { .init(weightKg: $0.weight, reps: $0.reps) },
                repLadders: sessionsOldestFirst.map {
                    $0.sorted { $0.order < $1.order }.map(\.reps)
                },
                firstWorkingWeightKg: last.first(where: { $0.weight > 0 })?.weight,
                generalRepLadders: general,
                weightSamples: working.filter { $0.weight > 0 }.map {
                    SetSample(weight: $0.weight, reps: $0.reps, date: $0.completedAt)
                })
        }

        private func matchingExercises(named name: String) -> [Exercise] {
            let keys = PartnerPlanResolver.historyLookupKeys(forExerciseNamed: name)
            guard !keys.isEmpty else { return [] }
            var found: [Exercise] = []
            var seen = Set<UUID>()
            for key in keys {
                for exercise in exercisesByName[key] ?? [] where seen.insert(exercise.id).inserted {
                    found.append(exercise)
                }
                for exercise in exercisesByKey[key] ?? [] where seen.insert(exercise.id).inserted {
                    found.append(exercise)
                }
            }
            return found
        }

        private func sessionDate(_ sets: [SetEntry]) -> Date {
            sets.first?.session?.date ?? sets.first?.completedAt ?? .distantPast
        }

        private func generalRepLadders(performerID: UUID?) -> [[Int]] {
            sessions
                .sorted { $0.date < $1.date }
                .suffix(20)
                .compactMap { session -> [Int]? in
                    let reps = session.orderedSets
                        .filter { !$0.isWarmup && matches($0, performerID: performerID) }
                        .map(\.reps)
                        .filter { $0 > 0 }
                    return reps.isEmpty ? nil : reps
                }
        }
    }

    /// Read-only lookup: the plan editor must never create an `Exercise` row for
    /// a movement the user has merely been shown.
    static func existingExercise(named name: String, in context: ModelContext) -> Exercise? {
        let all = (try? WorkoutRepository.allExercises(context)) ?? []
        return all.first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    /// `performerID == nil` is the device owner.
    static func history(forExerciseNamed name: String,
                        performerID: UUID?,
                        people: [Person],
                        context: ModelContext) -> PartnerPlanResolver.ExerciseHistory {
        return Index(context: context).history(forExerciseNamed: name,
                                               performerID: performerID,
                                               people: people)
    }

    /// The performer's rep pattern across ALL movements, oldest first — what a
    /// partner who has never trained *this* lift still tells us about how they
    /// like to work (decision D13, step 2).
    private static func generalRepLadders(performerID: UUID?,
                                          context: ModelContext) -> [[Int]] {
        let sessions = (try? WorkoutRepository.allSessions(context)) ?? []
        return sessions
            .sorted { $0.date < $1.date }
            .suffix(generalHistoryWindow)
            .compactMap { session -> [Int]? in
                let reps = session.orderedSets
                    .filter { !$0.isWarmup && matches($0, performerID: performerID) }
                    .map(\.reps)
                    .filter { $0 > 0 }
                return reps.isEmpty ? nil : reps
            }
    }

    /// Enough sessions to establish a pattern without walking a long history on
    /// every roster change.
    private static let generalHistoryWindow = 20

    private static func matches(_ set: SetEntry, performerID: UUID?) -> Bool {
        guard let performerID else { return set.isOwnerSet }
        return set.performedBy?.id == performerID
    }
}
