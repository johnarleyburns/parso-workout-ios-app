import Foundation
import CadenceCore

public struct HomeDashboardState: Sendable, Equatable {
    public struct ProfileContext: Sendable, Equatable {
        public let goal: String
        public let experience: String
        public let ageText: String
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

        public init(loggedMinutes: Double, easyMinutes: Double, moderateMinutes: Double,
                    vigorousMinutes: Double, moderateEquivalentMinutes: Double,
                    targetMinutes: Double, citationID: String) {
            self.loggedMinutes = loggedMinutes
            self.easyMinutes = easyMinutes
            self.moderateMinutes = moderateMinutes
            self.vigorousMinutes = vigorousMinutes
            self.moderateEquivalentMinutes = moderateEquivalentMinutes
            self.targetMinutes = targetMinutes
            self.citationID = citationID
        }

        /// The one-line "why is this bigger than what I did" explanation.
        public var summary: String {
            let logged = Self.format(loggedMinutes)
            let equivalent = Self.format(moderateEquivalentMinutes)
            guard vigorousMinutes > 0 || easyMinutes > 0 else {
                return "\(logged) min logged this week."
            }
            return "\(logged) min logged counts as \(equivalent) moderate-equivalent min."
        }

        public var explanation: String {
            "Public-health guidance counts 150 moderate-equivalent minutes a week. "
                + "Vigorous work counts double and easy work counts half, so the bar "
                + "measures effort, not just time on the clock."
        }

        /// One row per intensity actually trained, for the expanded card.
        public var lines: [(label: String, minutes: String, credit: String)] {
            var rows: [(String, String, String)] = []
            if easyMinutes > 0 {
                rows.append(("Easy", "\(Self.format(easyMinutes)) min",
                             "\(Self.format(easyMinutes * 0.5)) min credited"))
            }
            if moderateMinutes > 0 {
                rows.append(("Moderate", "\(Self.format(moderateMinutes)) min",
                             "\(Self.format(moderateMinutes)) min credited"))
            }
            if vigorousMinutes > 0 {
                rows.append(("Vigorous", "\(Self.format(vigorousMinutes)) min",
                             "\(Self.format(vigorousMinutes * 2)) min credited"))
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
    public let suggestions: [HomeSuggestion]
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

public enum HomeDashboardPresenter {
    /// The first warning is fully visible; the rest are behind Show more.
    public static func visibleSuggestions(_ suggestions: [HomeSuggestion], expanded: Bool) -> [HomeSuggestion] {
        expanded ? suggestions : Array(suggestions.prefix(1))
    }

    public static func make(snapshot: CoachSnapshot, schedule: CoachSchedulePreferences,
                            goal: TrainingGoal, experience: ExperienceLevel,
                            userAge: Int?) -> HomeDashboardState {
        let balance = snapshot.decision.weeklyBalance
        let strengthTarget = Double(max(1, schedule.strengthDaysPerWeek))
        let strength = HomeDashboardState.Progress(completed: Double(balance.strengthDays), target: strengthTarget,
            displayText: "\(balance.strengthDays) of \(schedule.strengthDaysPerWeek) days",
            normalized: min(1, Double(balance.strengthDays) / strengthTarget))
        let cardio = HomeDashboardState.Progress(completed: balance.moderateEquivalentMinutes, target: 150,
            displayText: "\(Int(balance.moderateEquivalentMinutes.rounded())) of 150 min",
            normalized: min(1, max(0, balance.moderateEquivalentMinutes / 150)))
        let volume = volumeRows(
            setsByGroup: snapshot.engineObservation?.effectiveSetsByGroup
                ?? snapshot.facts.weeklySetsByGroup,
                                tracked: schedule.trackedMuscleGroups)
        // Averaged over the TRACKED rows only, so half a set of incidental neck
        // work cannot drag the headline number down.
        let averageSets = averageCappedSets(volume.filter(\.isTracked).map(\.sets))
        let volumeCoverage = HomeDashboardState.Progress(
            completed: averageSets, target: WeeklySetProgress.maximum,
            displayText: "\(format(averageSets)) avg sets",
            normalized: WeeklySetProgress.normalized(averageSets))
        let cardioDetail = HomeDashboardState.CardioDetail(
            loggedMinutes: balance.loggedAerobicMinutes,
            easyMinutes: balance.easyMinutesLogged,
            moderateMinutes: balance.moderateMinutesLogged,
            vigorousMinutes: balance.vigorousMinutesLogged,
            moderateEquivalentMinutes: balance.moderateEquivalentMinutes,
            targetMinutes: 150,
            citationID: CitationRegistry.ekelundActivityMortality2016.id)
        return .init(profileContext: .init(goal: goal.displayName, experience: experience.displayName,
                                           ageText: userAge.map(String.init) ?? "Age not set"),
                     strength: strength, cardio: cardio, volumeCoverage: volumeCoverage,
                     volume: volume,
                     cardioDetail: cardioDetail,
                     suggestions: suggestions(snapshot: snapshot, schedule: schedule))
    }

    /// Every tracked muscle group, plus any untracked group the user has actually
    /// trained, alphabetically by displayed name.
    public static func volumeRows(setsByGroup: [MuscleGroup: Double],
                                  tracked: Set<MuscleGroup> = MuscleGroup.defaultTracked)
    -> [HomeDashboardState.VolumeRow] {
        MuscleGroup.allCases.compactMap { group -> HomeDashboardState.VolumeRow? in
            let sets = setsByGroup[group] ?? 0
            let isTracked = tracked.contains(group)
            // An untracked group with no work is noise: the coach does not target
            // it and the user has not trained it, so it does not need a row.
            guard isTracked || sets > 0 else { return nil }
            let zone = WeeklySetProgress.zone(for: sets)
            return .init(group: group,
                         displayName: group.displayName,
                         scientificName: group.scientificName,
                         sets: sets,
                         zone: zone,
                         rangeText: zone.displayText,
                         normalized: WeeklySetProgress.normalized(sets),
                         isTracked: isTracked,
                         citationID: CitationRegistry.iversenTimeEfficient2021.id)
        }
        .sorted {
            let order = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            return order == .orderedSame ? $0.group.rawValue < $1.group.rawValue
                                         : order == .orderedAscending
        }
    }

    /// Convenience for callers holding a raw-value-keyed tally.
    public static func volumeRows(setsByMuscle: [String: Double],
                                  tracked: Set<MuscleGroup> = MuscleGroup.defaultTracked)
    -> [HomeDashboardState.VolumeRow] {
        var byGroup: [MuscleGroup: Double] = [:]
        for (id, sets) in setsByMuscle {
            guard let group = MuscleGroup.canonical(id) else { continue }
            byGroup[group, default: 0] += sets
        }
        return volumeRows(setsByGroup: byGroup, tracked: tracked)
    }

    private static func suggestions(snapshot: CoachSnapshot, schedule: CoachSchedulePreferences) -> [HomeSuggestion] {
        var candidates: [HomeSuggestion] = snapshot.decision.warnings.map {
            .init(id: $0.id, category: .safety, title: "Recovery note", message: $0.message,
                  citationID: $0.citationIds.first, sourceClaimKey: "warning:\($0.id)", priority: 100, confidence: 100)
        }
        // Keep Home suggestions to evidence-backed warnings. The selected
        // workout is rendered separately and does not compete with warnings.
        candidates += snapshot.insights.filter { $0.severity == .attention }.map { insight in
            let category: HomeSuggestion.Category = .volumeRecovery
            return .init(id: insight.id, category: category, title: insight.title, message: insight.message,
                         citationID: insight.citation.id, sourceClaimKey: "insight:\(insight.id)",
                         priority: insight.severity.rawValue, confidence: snapshot.decision.confidence.rawValue)
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.sourceClaimKey).inserted }.sorted {
            ($0.category.rawValue, -$0.priority, -$0.confidence, $0.id) <
            ($1.category.rawValue, -$1.priority, -$1.confidence, $1.id)
        }
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func averageCappedSets(_ sets: [Double]) -> Double {
        guard !sets.isEmpty else { return 0 }
        return sets.map { min(max($0, 0), WeeklySetProgress.maximum) }.reduce(0, +) / Double(sets.count)
    }
}
