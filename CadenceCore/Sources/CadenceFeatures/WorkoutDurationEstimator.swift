import Foundation
import CadenceCore

/// A transparent duration estimate for a planned strength workout. The
/// estimate is deliberately separate from the workout model: it is presentation
/// state and must never be persisted as if it were an observed duration.
public struct DurationEstimate: Equatable, Sendable {
    public enum Basis: Equatable, Sendable {
        case history(sessionCount: Int)
        case defaults
    }

    public let minutes: Int
    public let basis: Basis

    public init(minutes: Int, basis: Basis) {
        self.minutes = minutes
        self.basis = basis
    }

    public var explanation: String {
        switch basis {
        case .history(let count):
            return String(localized: "Based on the planned sets, rest times, and your pace over the last \(count) sessions.", bundle: .module)
        case .defaults:
            return String(localized: "Based on the planned sets and standard working-set and rest defaults.", bundle: .module)
        }
    }
}

public enum WorkoutDurationEstimator {
    public static let defaultWorkSeconds = 40.0
    public static let defaultRestSeconds = 90.0

    public static func estimate(plan: EditablePlan?, history: [WorkoutSession]) -> DurationEstimate? {
        guard let plan, !plan.exercises.isEmpty else { return nil }
        let setCount = plan.exercises.reduce(0) { $0 + $1.sets.count }
        guard setCount > 0 else { return nil }

        let samples = history.compactMap(workSecondsPerSet).filter { $0 > 0 }
        let workSeconds: Double
        let basis: DurationEstimate.Basis
        if samples.count >= 3 {
            workSeconds = median(samples).clamped(to: 25...90)
            basis = .history(sessionCount: samples.count)
        } else {
            workSeconds = defaultWorkSeconds
            basis = .defaults
        }

        // EditablePlan currently stores the set prescription but not rest
        // metadata; use the documented transparent default until that field is
        // promoted into the draft model.
        let plannedRest = Double(setCount) * defaultRestSeconds
        let transitions = max(0, plan.exercises.count - 1)
        let seconds = Double(plan.warmupMinutes + plan.cooldownMinutes) * 60
            + Double(setCount) * workSeconds
            + plannedRest
            + Double(transitions * 60)
        let rounded = max(5, Int((seconds / 60 / 5).rounded() * 5))
        return DurationEstimate(minutes: rounded, basis: basis)
    }

    private static func workSecondsPerSet(_ session: WorkoutSession) -> Double? {
        guard session.deletedAt == nil,
              session.endedAt != nil,
              session.completedOwnerWorkingSetCount > 0 else { return nil }
        let count = Double(session.completedOwnerWorkingSetCount)
        let rest = session.warmupSeconds + session.cooldownSeconds
        return (session.duration - rest) / count
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
