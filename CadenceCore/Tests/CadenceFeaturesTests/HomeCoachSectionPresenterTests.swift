import XCTest
import CadenceCore
@testable import CadenceFeatures

/// The Observations card has no hidden plan preview; the independent suggested
/// workout action is unconditional in its SwiftUI parent.
final class HomeCoachSectionPresenterTests: XCTestCase {
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
        let blocks = HomeCoachSectionPresenter.blocks(
            suggestions: [suggestion("a"), suggestion("b")], expanded: false)
        XCTAssertEqual(blocks.first, .heading)
        XCTAssertEqual(blocks, [.heading, .suggestion(suggestion("a")), .showMore(expanded: false)])
    }

    func testShowMoreOnlyAppearsWithMoreThanOneSuggestion() {
        XCTAssertFalse(HomeCoachSectionPresenter.blocks(suggestions: [suggestion("a")], expanded: false)
            .contains(.showMore(expanded: false)))
        XCTAssertTrue(HomeCoachSectionPresenter.blocks(suggestions: [suggestion("a"), suggestion("b")], expanded: false)
            .contains(.showMore(expanded: false)))
    }

    func testCollapsedAndExpandedVisibilityRemainCorrect() {
        let suggestions = [suggestion("a"), suggestion("b"), suggestion("c")]
        let collapsed = HomeCoachSectionPresenter.blocks(suggestions: suggestions, expanded: false)
        let expanded = HomeCoachSectionPresenter.blocks(suggestions: suggestions, expanded: true)
        XCTAssertEqual(ids(in: collapsed), ["a"])
        XCTAssertEqual(ids(in: expanded), ["a", "b", "c"])
    }

    func testToneRoleMapsPositiveWarningNeutral() {
        XCTAssertEqual(HomeCoachSectionPresenter.toneRole(.positive), .positive)
        XCTAssertEqual(HomeCoachSectionPresenter.toneRole(.warning), .warning)
        XCTAssertEqual(HomeCoachSectionPresenter.toneRole(.neutral), .neutral)
    }

    private func ids(in blocks: [HomeCoachSectionPresenter.Block]) -> [String] {
        blocks.compactMap { if case let .suggestion(suggestion) = $0 { suggestion.id } else { nil } }
    }
}
