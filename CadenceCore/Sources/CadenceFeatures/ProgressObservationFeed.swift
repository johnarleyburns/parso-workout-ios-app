import Foundation
import CadenceCore

/// The observation list shown on Progress. Built from the same `CoachSnapshot`
/// and the same `HomeDashboardPresenter` ordering policy Home used, so the
/// move cannot change which observations exist or their order.
public struct ProgressObservationFeed: Equatable, Sendable {
    public let suggestions: [HomeSuggestion]

    public init(suggestions: [HomeSuggestion]) { self.suggestions = suggestions }

    public static let empty = ProgressObservationFeed(suggestions: [])

    public static func make(snapshot: CoachSnapshot, schedule: CoachSchedulePreferences,
                            goal: TrainingGoal, experience: ExperienceLevel,
                            userAge: Int?, dismissedKeys: Set<String> = []) -> ProgressObservationFeed {
        let state = HomeDashboardPresenter.make(snapshot: snapshot, schedule: schedule, goal: goal,
                                                experience: experience, userAge: userAge)
        return ProgressObservationFeed(suggestions: state.suggestions.filter {
            !dismissedKeys.contains($0.sourceClaimKey)
        })
    }

    public static func dismissedKeys(raw: String) -> Set<String> {
        Set(raw.split(separator: "|").map(String.init))
    }
}

/// Sections composing Today/Home's scrolling dashboard. Observations moved to
/// Progress and must not reappear here.
public enum TodayComposition {
    public enum Section: String, CaseIterable, Sendable { case dashboardTop }
    public static var sections: [Section] { Section.allCases }
}
