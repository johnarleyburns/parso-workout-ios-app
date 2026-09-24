import XCTest
@testable import CadenceFeatures

final class ProgressQuestionSelectionTests: XCTestCase {
    func testConsistencyIsTheSummaryFirstDefault() {
        XCTAssertEqual(ProgressQuestionSelection().selected, .consistency)
    }

    func testSelectingAnotherQuestionReplacesTheCurrentSummary() {
        var selection = ProgressQuestionSelection()

        selection.select(.personalRecords)
        XCTAssertEqual(selection.selected, .personalRecords)

        selection.select(.intensity)
        XCTAssertEqual(selection.selected, .intensity)
    }

    func testAlphabeticalIncludesEveryProgressSurface() {
        XCTAssertEqual(ProgressQuestion.alphabetical.map(\.displayName), [
            "Consistency", "Effort", "Exercise", "Intensity", "Personal Records",
            "Strength over time", "Tests"
        ])
    }
}
