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

    func testAlphabeticalIncludesEveryProgressSurface() {
        XCTAssertEqual(ProgressQuestion.alphabetical.map(\.displayName), [
            "Cardio", "Consistency", "Effort", "Exercise", "Frequency",
            "Intensity", "Muscle volume", "Strength over time", "Tests", "Trends"
        ])
    }
}
