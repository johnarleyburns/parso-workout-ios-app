import XCTest
import CadenceCore
@testable import CadenceFeatures

/// The Observations card has no hidden plan preview; the independent suggested
/// workout action is unconditional in its SwiftUI parent.
final class ObservationsPresenterTests: XCTestCase {
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

    func testHeadingIsAlwaysFirstAndNoWorkoutBlocksExist() {
        let blocks = ObservationsPresenter.blocks(
            suggestions: [suggestion("a"), suggestion("b")], expanded: false)
        XCTAssertEqual(blocks.first, .heading)
        XCTAssertEqual(blocks, [.heading, .suggestion(suggestion("a")), .showMore(expanded: false)])
    }

    func testShowMoreOnlyAppearsWithMoreThanOneSuggestion() {
        XCTAssertFalse(ObservationsPresenter.blocks(suggestions: [suggestion("a")], expanded: false)
            .contains(.showMore(expanded: false)))
        XCTAssertTrue(ObservationsPresenter.blocks(suggestions: [suggestion("a"), suggestion("b")], expanded: false)
            .contains(.showMore(expanded: false)))
    }

    func testCollapsedAndExpandedVisibilityRemainCorrect() {
        let suggestions = [suggestion("a"), suggestion("b"), suggestion("c")]
        let collapsed = ObservationsPresenter.blocks(suggestions: suggestions, expanded: false)
        let expanded = ObservationsPresenter.blocks(suggestions: suggestions, expanded: true)
        XCTAssertEqual(ids(in: collapsed), ["a"])
        XCTAssertEqual(ids(in: expanded), ["a", "b", "c"])
    }

    func testToneRoleMapsPositiveWarningNeutral() {
        XCTAssertEqual(ObservationsPresenter.toneRole(.positive), .positive)
        XCTAssertEqual(ObservationsPresenter.toneRole(.warning), .warning)
        XCTAssertEqual(ObservationsPresenter.toneRole(.neutral), .neutral)
    }

    private func ids(in blocks: [ObservationsPresenter.Block]) -> [String] {
        blocks.compactMap { if case let .suggestion(suggestion) = $0 { suggestion.id } else { nil } }
    }
}

final class ObservationsRoutingTests: XCTestCase {
    func testRoutingKeepsOwnersSeparate() {
        XCTAssertEqual(ProgressDataOwner.owner(for: .observations), .observations)
        XCTAssertEqual(ProgressDataOwner.owner(for: .workoutHistory), .pagedHistory)
    }

    func testEmptyFeedHasNoShowMore() {
        let blocks = ObservationsPresenter.blocks(suggestions: [], expanded: false)
        XCTAssertEqual(blocks, [.heading])
        XCTAssertTrue(ObservationsPresenter.isEmpty(suggestions: []))
    }

    func testTodayCompositionHasNoObservations() {
        XCTAssertFalse(TodayComposition.sections.contains { $0.rawValue.lowercased().contains("observation") })
    }

    func testFeedMatchesHomePresenterOrderAndFiltersDismissed() {
        let snapshot = CoachSnapshotBuilder.build(
            sessions: [], cardio: [], assessments: [], hasPainToday: false,
            goal: .strength, experience: .intermediate, formula: .epley,
            schedulePreferences: CoachSchedulePreferences(), profile: .empty)
        let schedule = CoachSchedulePreferences()
        let home = HomeDashboardPresenter.make(snapshot: snapshot, schedule: schedule, goal: .strength,
                                               experience: .intermediate, userAge: nil).suggestions
        let feed = ProgressObservationFeed.make(snapshot: snapshot, schedule: schedule, goal: .strength,
                                                experience: .intermediate, userAge: nil)
        XCTAssertEqual(feed.suggestions.map(\.id), home.map(\.id))
        let dismissed = ProgressObservationFeed.make(
            snapshot: snapshot, schedule: schedule, goal: .strength, experience: .intermediate,
            userAge: nil, dismissedKeys: Set(home.map(\.sourceClaimKey)))
        XCTAssertTrue(dismissed.suggestions.isEmpty)
    }
}
