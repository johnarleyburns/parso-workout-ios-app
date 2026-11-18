import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

/// The Observations card has no hidden plan preview; the independent suggested
/// workout action is unconditional in its SwiftUI parent.
struct ObservationsPresenterTests {
    private func suggestion(_ id: String, tone: HomeSuggestion.Tone = .neutral) -> HomeSuggestion {
        HomeSuggestion(id: id,
                       category: tone == .warning ? .safety : .progress,
                       title: "Title \(id)",
                       message: "Message \(id)",
                       citationID: nil,
                       sourceClaimKey: "claim.\(id)",
                       priority: 0,
                       confidence: 3)
    }

    @Test func headingIsAlwaysFirstAndNoWorkoutBlocksExist() {
        let blocks = ObservationsPresenter.blocks(
            suggestions: [suggestion("a"), suggestion("b")], expanded: false)
        #expect(blocks.first == .heading)
        #expect(blocks == [.heading, .suggestion(suggestion("a")), .showMore(expanded: false)])
    }

    @Test func showMoreOnlyAppearsWithMoreThanOneSuggestion() {
        #expect(!ObservationsPresenter.blocks(suggestions: [suggestion("a")], expanded: false)
            .contains(.showMore(expanded: false)))
        #expect(ObservationsPresenter.blocks(suggestions: [suggestion("a"), suggestion("b")], expanded: false)
            .contains(.showMore(expanded: false)))
    }

    @Test func collapsedAndExpandedVisibilityRemainCorrect() {
        let suggestions = [suggestion("a"), suggestion("b"), suggestion("c")]
        let collapsed = ObservationsPresenter.blocks(suggestions: suggestions, expanded: false)
        let expanded = ObservationsPresenter.blocks(suggestions: suggestions, expanded: true)
        #expect(ids(in: collapsed) == ["a"])
        #expect(ids(in: expanded) == ["a", "b", "c"])
    }

    @Test func toneRoleMapsPositiveWarningNeutral() {
        #expect(ObservationsPresenter.toneRole(.positive) == .positive)
        #expect(ObservationsPresenter.toneRole(.warning) == .warning)
        #expect(ObservationsPresenter.toneRole(.neutral) == .neutral)
    }

    private func ids(in blocks: [ObservationsPresenter.Block]) -> [String] {
        blocks.compactMap { if case let .suggestion(suggestion) = $0 { suggestion.id } else { nil } }
    }
}

struct ObservationsRoutingTests {
    @Test func routingKeepsOwnersSeparate() {
        #expect(ProgressDataOwner.owner(for: .observations) == .observations)
        #expect(ProgressDataOwner.owner(for: .workoutHistory) == .pagedHistory)
    }

    @Test func emptyFeedHasNoShowMore() {
        let blocks = ObservationsPresenter.blocks(suggestions: [], expanded: false)
        #expect(blocks == [.heading])
        #expect(ObservationsPresenter.isEmpty(suggestions: []))
    }

    @Test func todayCompositionHasNoObservations() {
        #expect(!TodayComposition.sections.contains { $0.rawValue.lowercased().contains("observation") })
    }

    @Test func feedMatchesHomePresenterOrderAndFiltersDismissed() {
        let snapshot = CoachSnapshotBuilder.build(
            sessions: [], cardio: [], assessments: [], hasPainToday: false,
            goal: .strength, experience: .intermediate, formula: .epley,
            schedulePreferences: CoachSchedulePreferences(), profile: .empty)
        let schedule = CoachSchedulePreferences()
        let home = HomeDashboardPresenter.make(snapshot: snapshot, schedule: schedule, goal: .strength,
                                               experience: .intermediate, userAge: nil).suggestions
        let feed = ProgressObservationFeed.make(snapshot: snapshot, schedule: schedule, goal: .strength,
                                                experience: .intermediate, userAge: nil)
        #expect(feed.suggestions.map(\.id) == home.map(\.id))
        let dismissed = ProgressObservationFeed.make(
            snapshot: snapshot, schedule: schedule, goal: .strength, experience: .intermediate,
            userAge: nil, dismissedKeys: Set(home.map(\.sourceClaimKey)))
        #expect(dismissed.suggestions.isEmpty)
    }
}
