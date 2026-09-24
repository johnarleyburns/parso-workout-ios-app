import XCTest
@testable import CadenceFeatures

final class ProgressQuestionSelectionTests: XCTestCase {
    func testStrengthOverTimeIsTheDefault() {
        XCTAssertEqual(ProgressQuestionSelection().selected, .strengthOverTime)
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
            "Consistency", "Effort", "Intensity", "Personal Records",
            "Strength over time", "Tests", "Workout History"
        ])
    }

    func testSelectionPersistsAndDefaultsToStrengthOverTime() {
        let suite = "ProgressQuestionSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(ProgressQuestionSelection.persisted(defaults: defaults).selected,
                       .strengthOverTime)
        let selection = ProgressQuestionSelection(selected: .personalRecords)
        selection.persist(defaults: defaults)
        XCTAssertEqual(ProgressQuestionSelection.persisted(defaults: defaults).selected,
                       .personalRecords)
    }
}
