import Foundation
import SwiftData
import CadenceCore

/// Builds the bounded `WatchSetDefaultSnapshot` from phone SwiftData history.
/// Pure and side-effect free: no WatchConnectivity, no writes. Call it off the
/// main actor (the Watch-payload background task), never from a view `body`.
public struct WatchSetDefaultSnapshotBuilder {
    public static let defaultSessionLimit = 21

    /// Most recent completed sessions (`endedAt` set or logged), non-deleted.
    public static func make(context: ModelContext,
                            now: Date = .now,
                            sessionLimit: Int = defaultSessionLimit) throws -> WatchSetDefaultSnapshot {
        guard sessionLimit > 0 else { return WatchSetDefaultSnapshot(generatedAt: now, performers: []) }
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.deletedAt == nil && ($0.endedAt != nil || $0.isLogged) },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = sessionLimit
        let sessions = try context.fetch(descriptor).sorted { $0.date < $1.date }
        return build(sessions: sessions, now: now)
    }

    private struct ExerciseAccumulator {
        var displayName: String
        var ladders: [[Int]] = []
        var samples: [WatchSetDefaultSnapshot.Sample] = []
        var firstWorkingWeightKg: Double?
    }

    private struct PerformerAccumulator {
        var displayName: String
        var exercises: [String: ExerciseAccumulator] = [:]
        var general: [[Int]] = []
    }

    /// `sessions` must be oldest → newest.
    static func build(sessions: [WorkoutSession], now: Date) -> WatchSetDefaultSnapshot {
        var performers: [String: PerformerAccumulator] = [:]
        for session in sessions {
            var sessionLadders: [String: [Int]] = [:]
            var exerciseLadders: [String: [String: [Int]]] = [:]
            var exerciseFirstSeen: [String: [String: Double?]] = [:]
            for set in session.orderedSets {
                let person = set.isOwnerSet ? nil : set.performedBy
                let pid = person?.id.uuidString ?? WatchSetDefaultSnapshot.ownerID
                let name = set.exercise?.name ?? set.exerciseNameSnapshot ?? ""
                let key = WatchSetDefaultSnapshot.canonicalKey(name)
                if performers[pid] == nil {
                    performers[pid] = PerformerAccumulator(
                        displayName: person?.name ?? set.performedBy?.name ?? "Me")
                }
                if !key.isEmpty {
                    var acc = performers[pid]!.exercises[key] ?? ExerciseAccumulator(displayName: name)
                    acc.displayName = name
                    performers[pid]!.exercises[key] = acc
                    // Mirrors WorkoutRepository.firstWorkingSetWeight: first working
                    // load among all of the performer's sets in the session.
                    if exerciseFirstSeen[pid, default: [:]][key] == nil {
                        exerciseFirstSeen[pid, default: [:]][key] = .some(nil)
                    }
                    if !set.isWarmup, set.weight.isFinite, set.weight > 0,
                       exerciseFirstSeen[pid]![key]! == nil {
                        exerciseFirstSeen[pid]![key] = .some(set.weight)
                    }
                }
                guard !set.isWarmup, set.reps > 0 else { continue }
                sessionLadders[pid, default: []].append(set.reps)
                guard !key.isEmpty else { continue }
                exerciseLadders[pid, default: [:]][key, default: []].append(set.reps)
                if set.weight.isFinite, set.weight > 0 {
                    performers[pid]!.exercises[key]!.samples.append(
                        .init(weightKg: set.weight, reps: set.reps))
                }
            }
            for (pid, ladder) in sessionLadders { performers[pid]!.general.append(ladder) }
            for (pid, byKey) in exerciseLadders {
                for (key, ladder) in byKey { performers[pid]!.exercises[key]!.ladders.append(ladder) }
            }
            // Latest session containing the performer's sets wins.
            for (pid, byKey) in exerciseFirstSeen {
                for (key, weight) in byKey { performers[pid]!.exercises[key]!.firstWorkingWeightKg = weight }
            }
        }
        let rows = performers.keys.sorted { a, b in
            if a == WatchSetDefaultSnapshot.ownerID { return true }
            if b == WatchSetDefaultSnapshot.ownerID { return false }
            return a < b
        }.map { pid -> WatchSetDefaultSnapshot.Performer in
            let p = performers[pid]!
            let exercises = p.exercises.keys.sorted().map { key -> WatchSetDefaultSnapshot.Exercise in
                let e = p.exercises[key]!
                return .init(id: key, displayName: e.displayName, repLadders: e.ladders,
                             samples: e.samples, firstWorkingWeightKg: e.firstWorkingWeightKg)
            }
            return .init(id: pid, displayName: p.displayName, exercises: exercises,
                         generalRepLadders: p.general)
        }
        return WatchSetDefaultSnapshot(generatedAt: now, performers: rows)
    }
}
