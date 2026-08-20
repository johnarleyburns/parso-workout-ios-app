import Foundation
import CadenceCore

/// The non-UI contract for the expanded iPhone set editor. Weight is kept in
/// display units until `canonicalWeightKg`; this avoids conversion/rounding
/// drift while the user edits unrelated fields.
public struct ExpandedSetDraftModel: Equatable, Sendable {
    public static let minReps = 1
    public static let maxReps = 100
    public static let maxWeight = 1000.0

    public let unit: MeasurementUnitPreference
    public private(set) var weight: Double
    public private(set) var reps: Int
    public private(set) var effort: Double?
    public private(set) var effortMode: WatchEffortMode
    public private(set) var hasSubmitted = false

    public init(weight: Double, reps: Int, rpe: Double?, unit: MeasurementUnitPreference,
                effortMode: WatchEffortMode = .rpe) {
        self.unit = unit
        self.weight = Self.clampWeight(weight)
        self.reps = min(max(reps, Self.minReps), Self.maxReps)
        self.effortMode = effortMode
        self.effort = rpe.flatMap { effortMode == .rpe ? Self.clampEffort($0) : Self.clampEffort(10 - $0) }
    }

    public static func increments(for unit: MeasurementUnitPreference) -> [Double] {
        switch unit {
        case .pounds: return [45, 35, 25, 10, 5, 2.5, 0.25]
        case .kilograms: return [20, 15, 10, 5, 2.5, 1.25, 0.25]
        }
    }

    public var canonicalWeightKg: Double { WorkoutMath.canonical(weight, from: unit) }

    public mutating func adjustWeight(by amount: Double) {
        weight = Self.clampWeight(weight + amount)
    }

    public mutating func setWeight(_ value: Double) {
        weight = Self.clampWeight(value)
    }

    /// Retargets the rep count outright — used when the editor switches to a
    /// different performer mid-entry (field test 2026-08-19 #2).
    public mutating func setReps(_ value: Int) {
        reps = min(max(value, Self.minReps), Self.maxReps)
    }

    public mutating func adjustReps(by amount: Int) {
        reps = min(max(reps + amount, Self.minReps), Self.maxReps)
    }

    public mutating func selectEffort(_ value: Double?) {
        effort = value.map(Self.clampEffort)
    }

    public mutating func selectMode(_ mode: WatchEffortMode) {
        guard mode != effortMode else { return }
        if let currentEffort = effort {
            let canonicalRPE = effortMode.rpeValue(from: currentEffort)
            self.effort = canonicalRPE.map { mode == .rpe ? $0 : 10 - $0 }.map(Self.clampEffort)
        }
        effortMode = mode
    }

    /// Returns at most one draft. Calling it again while a write is in flight
    /// (or after success) cannot create a duplicate set.
    public mutating func submit() -> (weight: Double, reps: Int, rpe: Double?)? {
        guard !hasSubmitted else { return nil }
        hasSubmitted = true
        return (weight, reps, effortMode.rpeValue(from: effort))
    }

    public static func clampWeight(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), maxWeight)
    }

    private static func clampEffort(_ value: Double) -> Double {
        min(10, max(1, value.rounded()))
    }
}
