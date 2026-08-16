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

    public enum VolumeRangeStatus: String, Sendable, Equatable {
        case belowStartingRange
        case productive
        case aboveRecoveryRange

        public var accessibilityText: String {
            switch self {
            case .belowStartingRange: return "Below starting range"
            case .productive: return "Within productive range"
            case .aboveRecoveryRange: return "Above recovery range"
            }
        }
    }

    public struct VolumeRow: Sendable, Equatable, Identifiable {
        public let part: BodyPart
        public let displayName: String
        public let sets: Double
        public let rangeStatus: String
        public let status: VolumeRangeStatus
        public let normalized: Double
        public let citationID: String
        public var id: BodyPart { part }
    }
    public let profileContext: ProfileContext
    public let strength: Progress
    public let cardio: Progress
    /// Number of body parts currently in the productive (green) range.
    public let volumeCoverage: Progress
    public let volume: [VolumeRow]
    public let suggestions: [HomeSuggestion]
}

public struct HomeSuggestion: Sendable, Equatable, Identifiable {
    public enum Category: Int, Sendable, Equatable { case safety, weeklyDeficit, volumeRecovery, planAction, progress }
    public let id: String
    public let category: Category
    public let title: String
    public let message: String
    public let citationID: String?
    public let sourceClaimKey: String
    public let priority: Int
    public let confidence: Int
}

public enum HomeDashboardPresenter {
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
        let volume = BodyPart.allCases.map { part -> HomeDashboardState.VolumeRow in
            let sets = snapshot.facts.weeklySetsByPart[part] ?? 0
            let bands = VolumeLandmarks.bands(for: part, experience: experience)
            let rangeStatus: HomeDashboardState.VolumeRangeStatus
            if sets > bands.mrv { rangeStatus = .aboveRecoveryRange }
            else if sets >= bands.mev { rangeStatus = .productive }
            else { rangeStatus = .belowStartingRange }
            return .init(part: part, displayName: part == .abs ? "Core" : part.displayName, sets: sets,
                         rangeStatus: rangeStatus.accessibilityText, status: rangeStatus,
                         normalized: min(1, max(0, sets / max(1, bands.mav))),
                         citationID: CitationRegistry.volumeDoseResponse.id)
        }
        let productiveParts = volume.filter { $0.status == .productive }.count
        let volumeCoverage = HomeDashboardState.Progress(
            completed: Double(productiveParts), target: 8,
            displayText: "\(productiveParts)/8 body parts",
            normalized: min(1, Double(productiveParts) / 8))
        return .init(profileContext: .init(goal: goal.displayName, experience: experience.displayName,
                                           ageText: userAge.map(String.init) ?? "Age not set"),
                     strength: strength, cardio: cardio, volumeCoverage: volumeCoverage,
                     volume: volume,
                     suggestions: suggestions(snapshot: snapshot, schedule: schedule))
    }

    private static func suggestions(snapshot: CoachSnapshot, schedule: CoachSchedulePreferences) -> [HomeSuggestion] {
        let balance = snapshot.decision.weeklyBalance
        var candidates: [HomeSuggestion] = snapshot.decision.warnings.map {
            .init(id: $0.id, category: .safety, title: "Recovery note", message: $0.message,
                  citationID: $0.citationIds.first, sourceClaimKey: "warning:\($0.id)", priority: 100, confidence: 100)
        }
        if balance.strengthDays < schedule.strengthDaysPerWeek {
            candidates.append(.init(id: "week-strength", category: .weeklyDeficit, title: "Strength target is not complete",
                message: "You have completed \(balance.strengthDays) of \(schedule.strengthDaysPerWeek) strength days this week.",
                citationID: nil, sourceClaimKey: "weekly-strength-deficit", priority: 80, confidence: 100))
        }
        if balance.moderateEquivalentMinutes < 150 {
            candidates.append(.init(id: "week-cardio", category: .weeklyDeficit, title: "Cardio target is not complete",
                message: "You have \(Int(balance.moderateEquivalentMinutes.rounded())) of 150 moderate-equivalent minutes.",
                citationID: nil, sourceClaimKey: "weekly-cardio-deficit", priority: 80, confidence: 100))
        }
        candidates += snapshot.insights.map { insight in
            let category: HomeSuggestion.Category = insight.kind == .volume ? .volumeRecovery :
                (insight.kind == .assessment ? .planAction : .progress)
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
}
