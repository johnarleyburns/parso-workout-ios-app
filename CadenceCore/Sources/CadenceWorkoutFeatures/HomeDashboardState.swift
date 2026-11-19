import CadenceFeatures
import Foundation
import CadenceCore

public struct HomeDashboardState: Sendable, Equatable {
    public struct ProfileContext: Sendable, Equatable {
        public let goal: String
        public let experience: String
        public let ageText: String

        public init(goal: String, experience: String, ageText: String) {
            self.goal = goal
            self.experience = experience
            self.ageText = ageText
        }
    }
    public struct Progress: Sendable, Equatable {
        public let completed: Double
        public let target: Double
        public let displayText: String
        public let normalized: Double

        public init(completed: Double, target: Double, displayText: String, normalized: Double) {
            self.completed = completed
            self.target = target
            self.displayText = displayText
            self.normalized = normalized
        }

        public var isAtOrAboveTarget: Bool { completed >= target }
    }

    /// One muscle group's progress toward the weekly set target.
    ///
    /// This is the only per-muscle list Home shows. It replaced the pair of rows
    /// that measured the same thing at two resolutions — a coarse eight-bucket
    /// `Volume` and a fine `Muscles` — with the one resolution the evidence
    /// actually supports (DB++ adoption, decision D5).
    public struct VolumeRow: Sendable, Equatable, Identifiable {
        public let group: MuscleGroup
        public let displayName: String
        /// Scientific name, e.g. "Gluteus Maximus".
        public let scientificName: String
        public let sets: Double
        public let zone: WeeklySetZone
        public let rangeText: String
        /// 0…1, clamped — the fraction of the 12-set scale completed.
        public let normalized: Double
        /// False for a group the user does not track: shown because it has volume,
        /// not because the coach targets it (decision D4).
        public let isTracked: Bool
        public let citationID: String
        public var id: MuscleGroup { group }

        public init(group: MuscleGroup, displayName: String, scientificName: String,
                    sets: Double, zone: WeeklySetZone, rangeText: String,
                    normalized: Double, isTracked: Bool, citationID: String) {
            self.group = group
            self.displayName = displayName
            self.scientificName = scientificName
            self.sets = sets
            self.zone = zone
            self.rangeText = rangeText
            self.normalized = normalized
            self.isTracked = isTracked
            self.citationID = citationID
        }
    }

    /// The weekly aerobic total, broken out so "158 of 150 min" from 80 logged
    /// minutes is explainable rather than alarming (field test 2026-08-19 #7).
    public struct CardioDetail: Sendable, Equatable {
        public let loggedMinutes: Double
        public let easyMinutes: Double
        public let moderateMinutes: Double
        public let vigorousMinutes: Double
        public let moderateEquivalentMinutes: Double
        public let targetMinutes: Double
        public let citationID: String
        public let citationIDs: [String]
        public let belowModerateMinutes: Double
        public let unclassifiedMinutes: Double
        public let zoneMinutes: [TrainingZone: Double]
        public let algorithmVersion: CardioAlgorithmVersion

        public init(loggedMinutes: Double, easyMinutes: Double, moderateMinutes: Double,
                    vigorousMinutes: Double, moderateEquivalentMinutes: Double,
                    targetMinutes: Double, citationID: String,
                    citationIDs: [String] = [],
                    belowModerateMinutes: Double? = nil,
                    unclassifiedMinutes: Double = 0,
                    zoneMinutes: [TrainingZone: Double] = [:],
                    algorithmVersion: CardioAlgorithmVersion = .legacy) {
            self.loggedMinutes = loggedMinutes
            self.easyMinutes = easyMinutes
            self.moderateMinutes = moderateMinutes
            self.vigorousMinutes = vigorousMinutes
            self.moderateEquivalentMinutes = moderateEquivalentMinutes
            self.targetMinutes = targetMinutes
            self.citationID = citationID
            self.citationIDs = citationIDs.isEmpty ? [citationID] : citationIDs
            self.belowModerateMinutes = belowModerateMinutes ?? easyMinutes
            self.unclassifiedMinutes = unclassifiedMinutes
            self.zoneMinutes = zoneMinutes
            self.algorithmVersion = algorithmVersion
        }

        /// The one-line "why is this bigger than what I did" explanation.
        public var summary: String {
            let logged = Self.format(loggedMinutes)
            let equivalent = Self.format(moderateEquivalentMinutes)
            guard vigorousMinutes > 0 || easyMinutes > 0 else {
                return {
                    #if os(Linux)
                    "\(logged) min logged this week."
                    #else
                    String(localized: "\(logged) min logged this week.", bundle: FeatureLocalization.bundle)
                    #endif
                }()
            }
            return {
                #if os(Linux)
                "\(logged) min exercised produces \(equivalent) moderate-equivalent guideline credit."
                #else
                String(localized: "\(logged) min exercised produces \(equivalent) moderate-equivalent guideline credit.", bundle: FeatureLocalization.bundle)
                #endif
            }()
        }

        public var explanation: String {
            {
                #if os(Linux)
                "Public-health guidance counts 150 moderate-equivalent minutes a week. Vigorous work counts double. With resting HR, moderate is 40–<60% heart-rate reserve; without it, the app uses 50–<70% of maximum HR so its Z2 time receives moderate credit. Below-moderate activity receives no guideline credit."
                #else
                String(localized: "Public-health guidance counts 150 moderate-equivalent minutes a week. Vigorous work counts double. With resting HR, moderate is 40–<60% heart-rate reserve; without it, the app uses 50–<70% of maximum HR so its Z2 time receives moderate credit. Below-moderate activity receives no guideline credit.", bundle: FeatureLocalization.bundle)
                #endif
            }()
        }

        /// One row per intensity actually trained, for the expanded card.
        public var lines: [(label: String, minutes: String, credit: String)] {
            var rows: [(String, String, String)] = []
            if belowModerateMinutes > 0 {
                rows.append(({
                    #if os(Linux)
                    "Below moderate"
                    #else
                    String(localized: "Below moderate", bundle: FeatureLocalization.bundle)
                    #endif
                }(), "\(Self.format(belowModerateMinutes)) min",
                             "0 min credited"))
            }
            if moderateMinutes > 0 {
                rows.append(({
                    #if os(Linux)
                    "Moderate"
                    #else
                    String(localized: "Moderate", bundle: FeatureLocalization.bundle)
                    #endif
                }(), "\(Self.format(moderateMinutes)) min",
                             {
                                 #if os(Linux)
                                 "\(Self.format(moderateMinutes)) min credited"
                                 #else
                                 String(localized: "\(Self.format(moderateMinutes)) min credited", bundle: FeatureLocalization.bundle)
                                 #endif
                             }()))
            }
            if vigorousMinutes > 0 {
                rows.append(({
                    #if os(Linux)
                    "Vigorous"
                    #else
                    String(localized: "Vigorous", bundle: FeatureLocalization.bundle)
                    #endif
                }(), "\(Self.format(vigorousMinutes)) min",
                             {
                                 #if os(Linux)
                                 "\(Self.format(vigorousMinutes * 2)) min credited"
                                 #else
                                 String(localized: "\(Self.format(vigorousMinutes * 2)) min credited", bundle: FeatureLocalization.bundle)
                                 #endif
                             }()))
            }
            return rows
        }

        static func format(_ value: Double) -> String { String(Int(value.rounded())) }
    }
    public let profileContext: ProfileContext
    public let strength: Progress
    public let cardio: Progress
    /// Mean capped weekly sets across the tracked muscle groups.
    public let volumeCoverage: Progress
    /// Every tracked muscle group, plus any untracked one the user actually
    /// trained this week, ordered alphabetically by displayed name.
    public let volume: [VolumeRow]
    public let cardioDetail: CardioDetail
    public let activityDose: WeeklyActivitySummary?
    public let suggestions: [HomeSuggestion]

    public init(profileContext: ProfileContext, strength: Progress, cardio: Progress,
                volumeCoverage: Progress, volume: [VolumeRow], cardioDetail: CardioDetail,
                activityDose: WeeklyActivitySummary?, suggestions: [HomeSuggestion]) {
        self.profileContext = profileContext
        self.strength = strength
        self.cardio = cardio
        self.volumeCoverage = volumeCoverage
        self.volume = volume
        self.cardioDetail = cardioDetail
        self.activityDose = activityDose
        self.suggestions = suggestions
    }
}

public struct HomeSuggestion: Sendable, Equatable, Identifiable {
    public enum Category: Int, Sendable, Equatable { case safety, weeklyDeficit, volumeRecovery, planAction, progress }
    public enum Tone: String, Sendable, Equatable {
        case positive
        case warning
        case neutral
    }
    public let id: String
    public let category: Category
    public let title: String
    public let message: String
    public let citationID: String?
    public let sourceClaimKey: String
    public let priority: Int
    public let confidence: Int

    public init(id: String, category: Category, title: String, message: String,
                citationID: String?, sourceClaimKey: String, priority: Int, confidence: Int) {
        self.id = id
        self.category = category
        self.title = title
        self.message = message
        self.citationID = citationID
        self.sourceClaimKey = sourceClaimKey
        self.priority = priority
        self.confidence = confidence
    }

    /// Presentation tone for the Home warning list.
    public var tone: Tone {
        switch category {
        case .safety, .weeklyDeficit, .volumeRecovery: return .warning
        case .progress, .planAction: return .neutral
        }
    }
}
