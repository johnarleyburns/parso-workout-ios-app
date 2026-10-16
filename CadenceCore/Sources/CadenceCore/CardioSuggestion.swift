import Foundation

/// The two user-facing modalities behind Workout for You.
public enum SuggestedWorkoutModality: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case strength
    case cardio

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strength: return String(localized: "Strength", bundle: .module)
        case .cardio: return String(localized: "Cardio", bundle: .module)
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
    /// Modalities the user asked never to be suggested (injury, dislike, access).
    public let excludedTypes: Set<CardioType>

    public init(history: [CardioSuggestionHistory] = [],
                weeklyModerateEquivalentMinutes: Double,
                weeklyTargetMinutes: Double = 150,
                experience: ExperienceLevel = .intermediate,
                asOf: Date = Date(),
                excludedTypes: Set<CardioType> = []) {
        self.excludedTypes = excludedTypes
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
    /// Plain-language observation about recent training that motivated the pick.
    public let observation: String?

    public var id: String {
        "\(type.rawValue)-\(intensity.rawValue)-\(durationMinutes)"
    }

    public var isInterval: Bool { intensity == .interval }

    public init(type: CardioType, durationMinutes: Int,
                intensity: CardioSuggestionIntensity, indoor: Bool = true,
                warmupMinutes: Int = 5, cooldownMinutes: Int = 5,
                intervalRounds: Int? = nil, intervalWorkSeconds: Int? = nil,
                intervalRestSeconds: Int? = nil, rationale: String,
                citationIDs: [String], observation: String? = nil) {
        self.observation = observation
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
    public static let intervalHabitWindowDays = 28
    public static let minimumRecentIntervalSessions = 2
    public static let minimumDurationMinutes = 20
    public static let maximumDurationMinutes = 45

    /// Days without interval work before the generator recommends some.
    public static let intervalGapDays = 14
    /// Fallback order when history is empty or every past modality is excluded.
    private static let fallbackTypes: [CardioType] = [
        .run, .walk, .cycle, .elliptical, .rowing, .swim, .stairClimber
    ]
    private static let intervalCapable: Set<CardioType> = [
        .run, .cycle, .rowing, .swim, .elliptical, .stairClimber, .hiit, .boxing
    ]

    public static func generate(input: CardioSuggestionInput) -> CardioSuggestion? {
        let allowed = { (type: CardioType) in type != .other && !input.excludedTypes.contains(type) }
        let usableHistory = input.history
            .filter { allowed($0.type) && $0.durationMinutes > 0 }
            .sorted { $0.start > $1.start }
        // Preference first: the most recent allowed modality, else a fallback.
        guard let type = usableHistory.first?.type ?? fallbackTypes.first(where: allowed) else {
            return nil
        }
        let remaining = max(0, input.weeklyTargetMinutes - input.weeklyModerateEquivalentMinutes)
        let established = input.experience != .beginner
            && usableHistory.count >= minimumIntervalHistoryCount
            && usableHistory.prefix(7).reduce(0) { $0 + $1.moderateEquivalentMinutes }
                >= minimumIntervalBaseMinutes
        // An interval habit (e.g. Tabata, Norwegian 4x4, REHIT) is any interval
        // session in the recent window, even when the latest session was a run
        // or ride — intervals are logged as HIIT/boxing and must not be starved
        // just because they were not the very last workout.
        let windowStart = input.asOf.addingTimeInterval(-Double(intervalHabitWindowDays) * 86_400)
        let recentIntervals = usableHistory.filter { $0.isInterval && $0.start >= windowStart }
        let shouldSuggestIntervals = established
            && recentIntervals.count >= minimumRecentIntervalSessions

        let cutoff = input.asOf.addingTimeInterval(-Double(intervalGapDays) * 86_400)
        let noRecentIntervals = !input.history.contains { $0.isInterval && $0.start >= cutoff }
        let shortfall = remaining > 0
        let observation: String? = shortfall
            ? String(localized: "You are about \(Int(remaining.rounded())) minutes short of this week's cardio goal.", bundle: .module)
            : nil

        if established && noRecentIntervals && !shouldSuggestIntervals,
           let intervalType = ([type] + usableHistory.map(\.type))
            .first(where: { intervalCapable.contains($0) }) {
            return CardioSuggestion(
                type: intervalType,
                durationMinutes: 35,
                intensity: .interval,
                indoor: true,
                warmupMinutes: 5,
                cooldownMinutes: 5,
                intervalRounds: 4,
                intervalWorkSeconds: 240,
                intervalRestSeconds: 180,
                rationale: String(localized: "Norwegian 4×4: you have not done interval work in the past \(intervalGapDays) days. Four 4-minute hard efforts with easy recovery are an evidence-based way to raise maximal oxygen uptake (VO₂max) in a short session, using your preferred \(intervalType.displayName.lowercased()).", bundle: .module),
                citationIDs: ["hiitVo2max", "gillenSIT2016"],
                observation: observation ?? String(localized: "No interval training in the past \(intervalGapDays) days.", bundle: .module))
        }

        if shouldSuggestIntervals {
            let intervalType: CardioType = recentIntervals.first
                .map { $0.type == .boxing ? .boxing : .hiit } ?? .hiit
            return CardioSuggestion(
                type: intervalType,
                durationMinutes: 25,
                intensity: .interval,
                indoor: true,
                warmupMinutes: 5,
                cooldownMinutes: 5,
                intervalRounds: 4,
                intervalWorkSeconds: 120,
                intervalRestSeconds: 120,
                rationale: String(localized: "You have an established cardio base and recent interval work. This keeps the interval dose bounded while giving you a clear session to review.", bundle: .module),
                citationIDs: ["hiitVo2max"],
                observation: observation)
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
            rationale = String(localized: "This follows your recent \(type.displayName.lowercased()) history and contributes about \(duration) minutes toward this week's cardio gap.", bundle: .module)
        } else {
            rationale = String(localized: "Your weekly cardio target is covered, so this keeps your recent \(type.displayName.lowercased()) habit moving without adding unnecessary intensity.", bundle: .module)
        }
        return CardioSuggestion(
            type: type,
            durationMinutes: duration,
            intensity: .moderate,
            indoor: true,
            rationale: rationale,
            citationIDs: ["ekelundActivityMortality2016"],
            observation: observation)
    }
}
