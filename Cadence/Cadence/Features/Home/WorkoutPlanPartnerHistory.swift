import Foundation
import SwiftData
import CadenceCore
import CadenceFeatures

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
        private let exercisesByName: [String: Exercise]
        private let sessions: [WorkoutSession]

        init(context: ModelContext) {
            let exercises = (try? WorkoutRepository.allExercises(context)) ?? []
            exercisesByName = Dictionary(exercises.map { ($0.name.lowercased(), $0) },
                                         uniquingKeysWith: { first, _ in first })
            sessions = (try? WorkoutRepository.allSessions(context)) ?? []
        }

        func history(forExerciseNamed name: String,
                     performerID: UUID?,
                     people: [Person]) -> PartnerPlanResolver.ExerciseHistory {
            guard let exercise = exercisesByName[name.lowercased()] else {
                return PartnerPlanResolver.ExerciseHistory(
                    generalRepLadders: generalRepLadders(performerID: performerID))
            }
            let person = performerID.flatMap { id in people.first { $0.id == id } }
            let last = WorkoutRepository.lastTimeSets(for: exercise, performedBy: person, excluding: nil)
                .filter { !$0.isWarmup }
            return PartnerPlanResolver.ExerciseHistory(
                lastSets: last.map { .init(weightKg: $0.weight, reps: $0.reps) },
                repLadders: WorkoutRepository.repLadderHistory(for: exercise, performedBy: person, excluding: nil),
                firstWorkingWeightKg: WorkoutRepository.firstWorkingSetWeight(for: exercise,
                                                                               performedBy: person,
                                                                               excluding: nil),
                generalRepLadders: generalRepLadders(performerID: performerID))
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
