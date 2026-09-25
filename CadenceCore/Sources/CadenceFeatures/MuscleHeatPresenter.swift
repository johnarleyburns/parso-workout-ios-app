import Foundation
import CadenceCore

public enum BodySide: String, Sendable { case front, back }

public enum HeatLevel: Int, Sendable, Equatable {
    case none, low, mid, high, onTarget
}

public struct MuscleHeat: Equatable, Sendable, Identifiable {
    public let id: MuscleGroup
    public let sets: Double
    public let target: Double
    public let level: HeatLevel
    public let accessibilityLabel: String

    public init(id: MuscleGroup, sets: Double, target: Double, level: HeatLevel,
                accessibilityLabel: String) {
        self.id = id; self.sets = sets; self.target = target; self.level = level
        self.accessibilityLabel = accessibilityLabel
    }
}

public enum MuscleHeatPresenter {
    public static func heat(from weekly: [MuscleGroup: Double],
                            targets: [MuscleGroup: Double] = [:],
                            side: BodySide = .front) -> [MuscleHeat] {
        let visible = MuscleGroup.canonicalOrder.filter { group in
            switch side {
            case .front:
                return [.chest, .shoulders, .biceps, .abdominals, .quadriceps,
                        .adductors, .abductors, .forearms, .calves, .hipFlexors,
                        .tibialis].contains(group)
            case .back:
                return [.shoulders, .triceps, .lats, .middleBack, .lowerBack,
                        .glutes, .hamstrings, .calves, .forearms, .traps,
                        .rotatorCuff].contains(group)
            }
        }
        return visible.map { group in
            let sets = max(0, weekly[group] ?? 0)
            let target = max(0, targets[group] ?? 12)
            return MuscleHeat(id: group, sets: sets, target: target,
                              level: level(sets: sets, target: target),
                              accessibilityLabel: "\(group.displayName), \(format(sets)) of \(format(target)) sets")
        }
    }

    public static func level(sets: Double, target: Double) -> HeatLevel {
        guard target > 0, sets > 0 else { return .none }
        let ratio = sets / target
        switch ratio {
        case ..<(1.0 / 3.0): return .low
        case ..<0.5: return .mid
        case ..<0.75: return .high
        default: return .onTarget
        }
    }

    public static func mostBehind(_ all: [MuscleHeat], limit: Int = 3) -> [MuscleHeat] {
        all.sorted {
            let left = $0.target > 0 ? $0.sets / $0.target : 0
            let right = $1.target > 0 ? $1.sets / $1.target : 0
            return left == right ? MuscleGroup.canonicalIndex($0.id) < MuscleGroup.canonicalIndex($1.id) : left < right
        }.prefix(max(0, limit)).map { $0 }
    }

    public static func totals(_ all: [MuscleHeat]) -> (sets: Double, target: Double) {
        (all.reduce(0) { $0 + $1.sets }, all.reduce(0) { $0 + $1.target })
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
