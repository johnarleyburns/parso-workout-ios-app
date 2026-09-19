import Foundation
import CadenceCore
import CadenceFeatures

enum HomeWeeklyVolumeProjection {
    struct Result {
        let volumes: [String: [MuscleGroup: Double]]
        let tonnage: [String: Double]
        let performers: [VolumeSummaryPerformer]
        let histories: [String: [HomeMuscleHistory]]
    }

    static func make(sessions: [WorkoutSession], since: Date, now: Date) -> Result {
        let weekSessions = sessions.filter {
            $0.deletedAt == nil && $0.countsAsStrengthHistory && $0.date >= since && $0.date <= now
        }
        let sets = weekSessions.flatMap(LiveWorkoutVolumeCalculator.sets(from:))
        var names: [String: String] = [VolumeSummaryPerformer.ownerKey: "Me"]
        for session in weekSessions {
            for set in session.orderedSets where !set.isWarmup {
                if let partner = set.performedBy, !partner.isMe {
                    names[partner.id.uuidString] = partner.name
                }
            }
        }
        let keys = [VolumeSummaryPerformer.ownerKey]
            + names.keys.filter { $0 != VolumeSummaryPerformer.ownerKey }.sorted()
        let performers = keys.map { key in
            key == VolumeSummaryPerformer.ownerKey
                ? .owner
                : VolumeSummaryPerformer(id: key, name: names[key] ?? "Partner",
                                         personID: UUID(uuidString: key))
        }
        let volumes = Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, LiveWorkoutVolumeCalculator.totals(sets, since: since, performerKey: key))
        })
        let tonnage = Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, weekSessions.flatMap { $0.orderedSets }.reduce(0.0) { total, set in
                let performerKey = set.isOwnerSet
                    ? VolumeSummaryPerformer.ownerKey
                    : set.performedBy?.id.uuidString ?? "unknown-partner"
                guard !set.isWarmup, performerKey == key else { return total }
                return total + set.effectiveLoadKg * Double(set.reps)
            })
        })
        let histories = Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, HomeMuscleHistoryPresenter.make(sessions: weekSessions,
                                                  since: since, now: now,
                                                  performerKey: key))
        })
        // Keep the existing solo This Week presentation completely unchanged.
        // The alternate data set is only meaningful when a second performer is
        // actually present, and its presence is what enables the radio bar.
        guard performers.count > 1 else {
            return Result(volumes: [:], tonnage: [:], performers: [], histories: [:])
        }
        return Result(volumes: volumes, tonnage: tonnage, performers: performers, histories: histories)
    }
}
