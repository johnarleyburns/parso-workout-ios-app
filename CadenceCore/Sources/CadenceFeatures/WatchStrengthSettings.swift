import Foundation
import CadenceCore

public struct WatchRepPattern: Equatable, Sendable, Identifiable {
    public var id: String { reps.map(String.init).joined(separator: "-") }
    public let title: String
    public let reps: [Int]

    public init(_ reps: [Int], title: String? = nil) {
        self.reps = reps
        self.title = title ?? reps.map(String.init).joined(separator: "-")
    }

    public static let popular: [WatchRepPattern] = [
        WatchRepPattern([12, 10, 8]),
        WatchRepPattern([12, 10, 8, 6]),
        WatchRepPattern([10, 10, 10]),
        WatchRepPattern([8, 8, 8]),
        WatchRepPattern([6, 6, 6]),
        WatchRepPattern([5, 5, 5]),
        WatchRepPattern([5, 3, 1]),
        WatchRepPattern([3, 3, 3]),
        WatchRepPattern([15, 12, 10]),
        WatchRepPattern([20, 15, 12]),
    ]

    public static let fallback = WatchRepPattern([12, 10, 8])

    public static func normalized(_ reps: [Int]) -> WatchRepPattern {
        let cleaned = reps.filter { $0 > 0 }
        guard !cleaned.isEmpty else { return fallback }
        if let match = popular.first(where: { $0.reps == cleaned }) { return match }
        return WatchRepPattern(cleaned)
    }
}

public enum WatchRestOptions {
    public static let popular = [20, 30, 60, 90]

    public static func normalized(_ seconds: Int) -> Int {
        popular.contains(seconds) ? seconds : 60
    }
}

public enum WatchEffortMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case rpe
    case rir

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rpe: return "RPE"
        case .rir: return "RIR"
        }
    }

    public func rpeValue(from selectedValue: Double?) -> Double? {
        guard let selectedValue else { return nil }
        let clamped = min(10, max(1, selectedValue.rounded()))
        switch self {
        case .rpe:
            return clamped
        case .rir:
            return min(10, max(1, 10 - clamped))
        }
    }
}
