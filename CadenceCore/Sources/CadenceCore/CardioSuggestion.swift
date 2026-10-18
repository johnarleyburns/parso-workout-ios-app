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
    /// HIIT protocol ids (`HIITProtocol.id`) the user asked never to be suggested.
    public let excludedProtocolIDs: Set<String>
    /// HIIT protocol ids skipped with "Suggest another" in this screen session only.
    public let skippedProtocolIDs: Set<String>

    public init(history: [CardioSuggestionHistory] = [],
                weeklyModerateEquivalentMinutes: Double,
                weeklyTargetMinutes: Double = 150,
                experience: ExperienceLevel = .intermediate,
                asOf: Date = Date(),
                excludedTypes: Set<CardioType> = [],
                excludedProtocolIDs: Set<String> = [],
                skippedProtocolIDs: Set<String> = []) {
        self.excludedTypes = excludedTypes
        self.excludedProtocolIDs = excludedProtocolIDs
        self.skippedProtocolIDs = skippedProtocolIDs
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
    /// Library HIIT protocol this suggestion is built from (`HIITProtocol.id`).
    public let protocolID: String?
    public let protocolName: String?

    public var id: String {
        "\(protocolID ?? type.rawValue)-\(intensity.rawValue)-\(durationMinutes)"
    }

    public var isInterval: Bool { intensity == .interval }

    public init(type: CardioType, durationMinutes: Int,
                intensity: CardioSuggestionIntensity, indoor: Bool = true,
                warmupMinutes: Int = 5, cooldownMinutes: Int = 5,
                intervalRounds: Int? = nil, intervalWorkSeconds: Int? = nil,
                intervalRestSeconds: Int? = nil, rationale: String,
                citationIDs: [String], observation: String? = nil,
                protocolID: String? = nil, protocolName: String? = nil) {
        self.observation = observation
        self.protocolID = protocolID
        self.protocolName = protocolName
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

/// A documented HIIT protocol from the interval library, with the citations
/// that back it. The Cardio for You suggestion only ever picks from these.
public struct HIITProtocol: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let plan: IntervalPlan
    public let citationIDs: [String]
    /// Short setup subtitle (e.g. "3 × 20s all-out / 2 min"), when the protocol has one.
    public let subtitle: String?
    /// Equipment cue shown with the protocol (e.g. stationary bicycle).
    public let modalityCue: String?
    /// All-out sprint protocols are opt-in: never suggested to beginners.
    public let isOptInSprint: Bool

    public init(id: String, name: String, plan: IntervalPlan, citationIDs: [String],
                subtitle: String? = nil, modalityCue: String? = nil, isOptInSprint: Bool = false) {
        self.id = id
        self.name = name
        self.plan = plan
        self.citationIDs = citationIDs
        self.subtitle = subtitle
        self.modalityCue = modalityCue
        self.isOptInSprint = isOptInSprint
    }

    /// Minutes of cardio credit: work phases count as vigorous (2x moderate
    /// minutes); warm-up, rest/recovery and cool-down count as moderate (1x).
    public var moderateEquivalentMinutes: Double {
        plan.phases.reduce(0) { $0 + $1.duration / 60 * ($1.kind == .work ? 2 : 1) }
    }
    public var totalMinutes: Double { plan.totalDuration / 60 }

    public static let library: [HIITProtocol] = [
        HIITProtocol(id: "rehit", name: "REHIT", plan: .rehit(),
                     citationIDs: ["metcalfeREHIT2012", "hiitVo2max"]),
        HIITProtocol(id: "gillen", name: "Gillen", plan: .gillen(),
                     citationIDs: ["gillenSIT2016"],
                     subtitle: "3 × 20s all-out / 2 min",
                     modalityCue: String(localized: "Stationary bicycle", bundle: .module),
                     isOptInSprint: true),
        HIITProtocol(id: "tabata", name: "Tabata", plan: .tabata(),
                     citationIDs: ["tabata1996", "hiitVo2max"]),
        HIITProtocol(id: "gibala", name: "Gibala", plan: .gibala(),
                     citationIDs: ["gibala2006", "hiitVo2max"]),
        HIITProtocol(id: "tenTwentyThirty", name: "10-20-30", plan: .tenTwentyThirty(),
                     citationIDs: ["gunnarsson1020302012", "hiitVo2max"]),
        HIITProtocol(id: "sit", name: "SIT (Wingate)", plan: .sit(),
                     citationIDs: ["slothSIT2013", "gillenSIT2016"]),
        HIITProtocol(id: "norwegian4x4", name: "Norwegian 4×4", plan: .norwegian4x4(),
                     citationIDs: ["hiitVo2max", "gillenSIT2016"]),
    ]

    public static func find(id: String) -> HIITProtocol? { library.first { $0.id == id } }
}

/// Cardio for You: only ever suggests a documented HIIT protocol from
/// `HIITProtocol.library` — never a custom interval workout.
public enum CardioSuggestionGenerator {
    /// Average moderate-equivalent cardio minutes still needed per remaining
    /// day of the calendar week, counting today.
    public static func requiredMinutesPerDay(input: CardioSuggestionInput,
                                             calendar: Calendar = .current) -> Double {
        let remaining = max(0, input.weeklyTargetMinutes - input.weeklyModerateEquivalentMinutes)
        // The training week starts on Monday regardless of locale.
        var calendar = calendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let today = calendar.startOfDay(for: input.asOf)
        var daysLeft = 1
        if let week = calendar.dateInterval(of: .weekOfYear, for: input.asOf) {
            let d = calendar.dateComponents([.day], from: today, to: week.end).day ?? 1
            daysLeft = max(1, d)
        }
        return remaining / Double(daysLeft)
    }

    public static func generate(input: CardioSuggestionInput,
                                calendar: Calendar = .current) -> CardioSuggestion? {
        guard !input.excludedTypes.contains(.hiit) else { return nil }
        let blocked = input.excludedProtocolIDs.union(input.skippedProtocolIDs)
        let candidates = HIITProtocol.library.filter {
            !blocked.contains($0.id) && !($0.isOptInSprint && input.experience == .beginner)
        }
        guard !candidates.isEmpty else { return nil }

        let perDay = requiredMinutesPerDay(input: input, calendar: calendar)
        // Shortest protocol whose credit covers the daily need; if none can,
        // the one giving the most credit.
        let byLength = candidates.sorted { $0.totalMinutes < $1.totalMinutes }
        let chosen = byLength.first { $0.moderateEquivalentMinutes >= perDay }
            ?? candidates.max { $0.moderateEquivalentMinutes < $1.moderateEquivalentMinutes }!

        let remaining = max(0, input.weeklyTargetMinutes - input.weeklyModerateEquivalentMinutes)
        let observation: String? = remaining > 0
            ? String(localized: "You are about \(Int(remaining.rounded())) minutes short of this week's cardio goal, roughly \(Int(perDay.rounded(.up))) minutes a day for the rest of the week.", bundle: .module)
            : nil
        let plan = chosen.plan
        let work = plan.phases.first { $0.kind == .work }
        let rest = plan.phases.first { $0.kind == .rest }
        let warmup = plan.phases.first { $0.kind == .warmup }
        let cooldown = plan.phases.last { $0.kind == .cooldown }
        return CardioSuggestion(
            type: .hiit,
            durationMinutes: Int(chosen.totalMinutes.rounded(.up)),
            intensity: .interval,
            indoor: true,
            warmupMinutes: Int(((warmup?.duration ?? 0) / 60).rounded()),
            cooldownMinutes: Int(((cooldown?.duration ?? 0) / 60).rounded()),
            intervalRounds: plan.workRounds,
            intervalWorkSeconds: work.map { Int($0.duration) },
            intervalRestSeconds: rest.map { Int($0.duration) },
            rationale: String(localized: "\(chosen.name) is the shortest documented HIIT protocol in the library that covers about \(Int(perDay.rounded(.up))) minutes of cardio a day (hard intervals count double). It runs \(Int(chosen.totalMinutes.rounded(.up))) minutes with a moderate warm-up, recovery and cool-down.", bundle: .module),
            citationIDs: chosen.citationIDs,
            observation: observation,
            protocolID: chosen.id,
            protocolName: chosen.name)
    }
}
