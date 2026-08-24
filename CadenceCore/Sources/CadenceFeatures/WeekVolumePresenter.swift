import Foundation
import CadenceCore

/// Pure presenter that turns the week's completed + planned volume into
/// per-muscle-group rows for the Your Plan screen. Shares the same
/// `PlanAwareWeeklyAccounting` as the insight engine so the screen and the nag can
/// never disagree (§1).
public enum WeekVolumePresenter {

    public typealias PartRow = GroupRow

    public struct GroupRow: Equatable, Identifiable {
        public enum Status: Equatable {
            case targetMet
            case onTrack
            case short(toGo: Double)
            case high
        }

        public let group: MuscleGroup
        public var displayName: String { group.displayName }
        public let doneSets: Double
        public let plannedSets: Double
        public let band: ClosedRange<Double>
        public let barFractionDone: Double
        public let barFractionPlanned: Double
        public let mevTickFraction: Double
        public let status: Status

        public var id: MuscleGroup { group }

        public var projectedSets: Double { doneSets + plannedSets }
    }

    public struct Summary: Equatable {
        public let doneSets: Double
        public let plannedSets: Double
        public let recommendedSets: Double
    }

    public static func rows(facts: TrainingFacts,
                            optimized: OptimizedCoachPlan,
                            tracked: Set<MuscleGroup> = MuscleGroup.defaultTracked) -> [GroupRow] {
        let accounting = PlanAwareWeeklyAccounting(completed: facts,
                                                    plannedStrengthSessions: optimized.plannedStrengthSessions)
        let experience = facts.experience

        // Groups the coach tracks, plus any the user has actually put work into or
        // that the plan still owes, so nothing with volume is invisible.
        var active = tracked
        for (group, sets) in accounting.completedSetsByGroup where sets > 0 { active.insert(group) }
        for (group, sets) in accounting.plannedRemainingSetsByGroup where sets > 0 { active.insert(group) }
        for part in optimized.unresolvedDeficits.keys {
            for group in MuscleGroup.allCases
            where BodyPart.part(forGroup: group) == part && tracked.contains(group) {
                active.insert(group)
            }
        }

        return MuscleGroup.canonicalOrder.filter { active.contains($0) }.map { group in
            let done = accounting.completedSetsByGroup[group] ?? 0
            let planned = accounting.plannedRemainingSetsByGroup[group] ?? 0
            let projected = done + planned

            let bands = VolumeLandmarks.bands(for: group, experience: experience)
            let mev = bands.mev
            let mav = bands.mav
            let mrv = bands.mrv
            let band: ClosedRange<Double> = mev ... mav

            // Bar fractions: scale is MAV, clamped 0...1
            let barDone = mav > 0 ? min(1, done / mav) : 0
            let barPlanned = mav > 0 ? min(1, max(0, (min(projected, mav) - done) / mav)) : 0
            let mevTick = mav > 0 ? min(1, mev / mav) : 0

            let status: GroupRow.Status
            if projected > mrv {
                status = .high
            } else if done >= mev {
                status = .targetMet
            } else if projected >= mev {
                status = .onTrack
            } else {
                // Exact nag parity: prefer the plan's own unresolved deficit for
                // this group's part, fall back to the gap calculation.
                let part = BodyPart.part(forGroup: group)
                let toGo: Double
                if let part, let deficit = optimized.unresolvedDeficits[part], deficit > 0 {
                    toGo = min(deficit, max(0, mev - projected))
                } else {
                    toGo = max(0, mev - projected)
                }
                status = .short(toGo: toGo)
            }

            return GroupRow(
                group: group,
                doneSets: done,
                plannedSets: planned,
                band: band,
                barFractionDone: barDone,
                barFractionPlanned: barPlanned,
                mevTickFraction: mevTick,
                status: status)
        }
    }

    public static func summary(rows: [GroupRow]) -> Summary {
        let done = rows.reduce(0) { $0 + $1.doneSets }
        let planned = rows.reduce(0) { $0 + $1.plannedSets }
        let recommended = rows.reduce(0) { total, row in
            total + VolumeLandmarks.productiveTarget(for: row.group, experience: .intermediate)
        }
        return Summary(doneSets: done, plannedSets: planned, recommendedSets: recommended)
    }
}
