import XCTest
@testable import CadenceFeatures

final class ProgressQuestionSelectionTests: XCTestCase {
    func testConsistencyIsTheSummaryFirstDefault() {
        XCTAssertEqual(ProgressQuestionSelection().selected, .consistency)
    }

    func testSelectingAnotherQuestionReplacesTheCurrentSummary() {
        var selection = ProgressQuestionSelection()

        selection.select(.muscleVolume)
        XCTAssertEqual(selection.selected, .muscleVolume)

        selection.select(.cardioChange)
        XCTAssertEqual(selection.selected, .cardioChange)
    }
}
