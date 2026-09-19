import Foundation

/// The two user-facing modalities behind Workout for You.
public enum SuggestedWorkoutModality: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case strength
    case cardio

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .cardio: return "Cardio"
        }
    }

    public var symbol: String {
        switch self {
        case .strength: return "figure.strengthtraining.traditional"
        case .cardio: return "figure.run"
        }
    }
}

public enum CardioSuggestionIntensity: String, Codable, Hashable, Sendable {
    case easy
    case moderate
    case interval

    public var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .interval: return "Intervals"
        }
    }
}

/// Value-only history used by the cardio suggestion solver. It deliberately
/// does not expose SwiftData models or HR samples.
public struct CardioSuggestionHistory: Codable, Equatable, Hashable, Sendable {
    public let type: CardioType
    public let durationMinutes: Double
    public let moderateEquivalentMinutes: Double
    public let intensity: RelativeIntensity
    public let isInterval: Bool
    public let isIndoor: Bool?
    public let start: Date

    public init(type: CardioType, durationMinutes: Double,
                moderateEquivalentMinutes: Double,
                intensity: RelativeIntensity = .unknown,
                isInterval: Bool = false, isIndoor: Bool? = nil,
                start: Date) {
        self.type = type
        self.durationMinutes = max(0, durationMinutes)
        self.moderateEquivalentMinutes = max(0, moderateEquivalentMinutes)
        self.intensity = intensity
        self.isInterval = isInterval
        self.isIndoor = isIndoor
        self.start = start
    }
}

public struct CardioSuggestionInput: Codable, Equatable, Sendable {
    public let history: [CardioSuggestionHistory]
    public let weeklyModerateEquivalentMinutes: Double
    public let weeklyTargetMinutes: Double
    public let experience: ExperienceLevel
    public let asOf: Date

    public init(history: [CardioSuggestionHistory] = [],
                weeklyModerateEquivalentMinutes: Double,
                weeklyTargetMinutes: Double = 150,
                experience: ExperienceLevel = .intermediate,
                asOf: Date = Date()) {
        self.history = history
        self.weeklyModerateEquivalentMinutes = max(0, weeklyModerateEquivalentMinutes)
        self.weeklyTargetMinutes = max(1, weeklyTargetMinutes)
        self.experience = experience
        self.asOf = asOf
    }
}

public struct CardioSuggestion: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let type: CardioType
    public let durationMinutes: Int
    public let intensity: CardioSuggestionIntensity
    public let indoor: Bool
    public let warmupMinutes: Int
    public let cooldownMinutes: Int
    public let intervalRounds: Int?
    public let intervalWorkSeconds: Int?
    public let intervalRestSeconds: Int?
    public let rationale: String
    public let citationIDs: [String]

    public var id: String {
        "\(type.rawValue)-\(intensity.rawValue)-\(durationMinutes)"
    }

    public var isInterval: Bool { intensity == .interval }

    public init(type: CardioType, durationMinutes: Int,
                intensity: CardioSuggestionIntensity, indoor: Bool = true,
                warmupMinutes: Int = 5, cooldownMinutes: Int = 5,
                intervalRounds: Int? = nil, intervalWorkSeconds: Int? = nil,
                intervalRestSeconds: Int? = nil, rationale: String,
                citationIDs: [String]) {
        self.type = type
        self.durationMinutes = max(1, durationMinutes)
        self.intensity = intensity
        self.indoor = indoor
        self.warmupMinutes = max(0, warmupMinutes)
        self.cooldownMinutes = max(0, cooldownMinutes)
        self.intervalRounds = intervalRounds
        self.intervalWorkSeconds = intervalWorkSeconds
        self.intervalRestSeconds = intervalRestSeconds
        self.rationale = rationale
        self.citationIDs = citationIDs
    }
}

/// Deterministic, conservative cardio suggestion logic. It uses only a value
/// snapshot and can therefore run away from the SwiftUI render path.
public enum CardioSuggestionGenerator {
    public static let minimumIntervalHistoryCount = 3
    public static let minimumIntervalBaseMinutes = 90.0
    public static let minimumDurationMinutes = 20
    public static let maximumDurationMinutes = 45

    public static func generate(input: CardioSuggestionInput) -> CardioSuggestion? {
        let usableHistory = input.history
            .filter { $0.type != .other && $0.durationMinutes > 0 }
            .sorted { $0.start > $1.start }
        let type = preferredType(from: usableHistory) ?? .run
        let remaining = max(0, input.weeklyTargetMinutes - input.weeklyModerateEquivalentMinutes)
        let established = input.experience != .beginner
            && usableHistory.count >= minimumIntervalHistoryCount
            && usableHistory.prefix(7).reduce(0) { $0 + $1.moderateEquivalentMinutes }
                >= minimumIntervalBaseMinutes
        let recentInterval = usableHistory.first?.isInterval == true
        let shouldSuggestIntervals = established && recentInterval
            && (type == .hiit || type == .boxing)

        if shouldSuggestIntervals {
            return CardioSuggestion(
                type: type,
                durationMinutes: 25,
                intensity: .interval,
                indoor: true,
                warmupMinutes: 5,
                cooldownMinutes: 5,
                intervalRounds: 4,
                intervalWorkSeconds: 120,
                intervalRestSeconds: 120,
                rationale: "You have an established cardio base and recent interval work. This keeps the interval dose bounded while giving you a clear session to review.",
                citationIDs: ["hiitVo2max"])
        }

        let recentAverage = usableHistory.prefix(4).map(\.durationMinutes).reduce(0, +)
            / Double(max(1, min(4, usableHistory.count)))
        let baseline = recentAverage > 0 ? recentAverage : 25
        let targetDuration = remaining > 0 ? min(Double(maximumDurationMinutes), max(20, remaining)) : baseline
        let duration = min(maximumDurationMinutes, max(minimumDurationMinutes, Int(targetDuration.rounded())))
        let rationale: String
        if usableHistory.isEmpty {
            rationale = "A moderate indoor starter gives you a manageable way to build cardio history. You can switch to outdoors before starting."
        } else if remaining > 0 {
            rationale = "This follows your recent \(type.displayName.lowercased()) history and contributes about \(duration) minutes toward this week's cardio gap."
        } else {
            rationale = "Your weekly cardio target is covered, so this keeps your recent \(type.displayName.lowercased()) habit moving without adding unnecessary intensity."
        }
        return CardioSuggestion(
            type: type,
            durationMinutes: duration,
            intensity: .moderate,
            indoor: true,
            rationale: rationale,
            citationIDs: ["ekelundActivityMortality2016"])
    }

    private static func preferredType(from history: [CardioSuggestionHistory]) -> CardioType? {
        let supported = history.first { $0.type != .other }?.type
        return supported
    }
}
