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

public struct WatchCustomStrengthDefaults: Equatable, Sendable {
    public var repPattern: WatchRepPattern
    public var restSeconds: Int
    public var selectedPartners: [String]
    public var partnerOptions: [String]

    public init(storedRepPattern: String,
                storedRestSeconds: Int,
                storedPartners: String,
                recentPartners: [String]) {
        self.repPattern = WatchRepPattern.normalized(Self.parseRepPattern(storedRepPattern))
        self.restSeconds = WatchRestOptions.normalized(storedRestSeconds)
        self.selectedPartners = Self.decodedPartners(from: storedPartners)
        self.partnerOptions = Self.unique(self.selectedPartners + recentPartners)
    }

    public static func parseRepPattern(_ raw: String) -> [Int] {
        raw.split(separator: "-").compactMap { Int($0) }
    }

    public static func decodedPartners(from raw: String) -> [String] {
        raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func encodedPartners(_ names: [String]) -> String {
        unique(names).joined(separator: "\n")
    }

    public static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  seen.insert(trimmed.lowercased()).inserted else { continue }
            out.append(trimmed)
        }
        return out
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

public enum WatchExerciseSearchPhase: Equatable, Sendable {
    case empty
    case searching
    case noMatches
    case matches
}

public enum WatchExerciseSearchPresenter {
    public static func phase(query: String,
                             isSearching: Bool,
                             resultCount: Int) -> WatchExerciseSearchPhase {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if isSearching { return .searching }
        return resultCount == 0 ? .noMatches : .matches
    }
}
