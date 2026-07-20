import Foundation
import CadenceCore

/// Pure presenter that turns the week's completed + planned volume into per-part
/// rows for the Your Plan screen. Shares the same `PlanAwareWeeklyAccounting` as
/// the insight engine so the screen and the nag can never disagree (§1).
public enum WeekVolumePresenter {

    public struct PartRow: Equatable, Identifiable {
        public enum Status: Equatable {
            case targetMet
            case onTrack
            case short(toGo: Double)
            case high
        }

        public let part: BodyPart
        public let doneSets: Double
        public let plannedSets: Double
        public let band: ClosedRange<Double>
        public let barFractionDone: Double
        public let barFractionPlanned: Double
        public let mevTickFraction: Double
        public let status: Status

        public var id: BodyPart { part }

        public var projectedSets: Double { doneSets + plannedSets }
    }

    public struct Summary: Equatable {
        public let doneSets: Double
        public let plannedSets: Double
        public let recommendedSets: Double
    }

    public static func rows(facts: TrainingFacts,
                            optimized: OptimizedCoachPlan,
                            excluded: Set<BodyPart> = []) -> [PartRow] {
        let accounting = PlanAwareWeeklyAccounting(completed: facts,
                                                    plannedStrengthSessions: optimized.plannedStrengthSessions)
        let experience = facts.experience

        // Parts that have any activity (done, planned, or unresolved deficit)
        // and are not excluded.
        var activeParts = Set<BodyPart>()
        for (p, v) in accounting.completedSetsByPart where v > 0 { activeParts.insert(p) }
        for (p, v) in accounting.plannedRemainingSetsByPart where v > 0 { activeParts.insert(p) }
        for p in optimized.unresolvedDeficits.keys { activeParts.insert(p) }
        activeParts.subtract(excluded)

        return BodyPart.allCases
            .filter { activeParts.contains($0) }
            .map { part in

            let done = accounting.completedSetsByPart[part] ?? 0
            let planned = accounting.plannedRemainingSetsByPart[part] ?? 0
            let projected = done + planned

            let bands = VolumeLandmarks.bands(for: part, experience: experience)
            let mev = bands.mev
            let mav = bands.mav
            let mrv = bands.mrv
            let band: ClosedRange<Double> = bands.mev ... bands.mav

            // Bar fractions: scale is MAV, clamped 0...1
            let barDone = mav > 0 ? min(1, done / mav) : 0
            let barPlanned = mav > 0 ? min(1, max(0, (min(projected, mav) - done) / mav)) : 0
            let mevTick = mav > 0 ? min(1, mev / mav) : 0

            let status: PartRow.Status
            if projected > mrv {
                status = .high
            } else if done >= mev {
                status = .targetMet
            } else if projected >= mev {
                status = .onTrack
            } else {
                // Exact nag parity: prefer unresolvedDeficits, fall back to gap calc
                let toGo: Double
                if let deficit = optimized.unresolvedDeficits[part], deficit > 0 {
                    toGo = deficit
                } else {
                    toGo = max(0, mev - projected)
                }
                status = .short(toGo: toGo)
            }

            return PartRow(
                part: part,
                doneSets: done,
                plannedSets: planned,
                band: band,
                barFractionDone: barDone,
                barFractionPlanned: barPlanned,
                mevTickFraction: mevTick,
                status: status)
        }
    }

    public static func summary(rows: [PartRow]) -> Summary {
        let done = rows.reduce(0) { $0 + $1.doneSets }
        let planned = rows.reduce(0) { $0 + $1.plannedSets }
        let recommended = rows.reduce(0) { total, row in
            total + VolumeLandmarks.productiveTarget(for: row.part, experience: .intermediate)
        }
        return Summary(doneSets: done, plannedSets: planned, recommendedSets: recommended)
    }
}
