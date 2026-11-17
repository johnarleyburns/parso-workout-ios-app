import XCTest
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

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

    func testAlphabeticalContainsEveryCaseExactlyOnce() {
        let list = ProgressQuestion.alphabetical
        XCTAssertEqual(list.count, ProgressQuestion.allCases.count - 1)
        XCTAssertEqual(Set(list), Set(ProgressQuestion.allCases.filter { $0 != .workoutHistory }))
        XCTAssertTrue(list.contains(.observations))
    }

    func testHistoryLivesOutsideProgress() {
        XCTAssertFalse(ProgressQuestion.alphabetical.contains(.workoutHistory))
        XCTAssertEqual(ProgressQuestionSelection(selected: .workoutHistory).selected, .strengthOverTime)
    }

    func testAlphabeticalIsLocalizedLabelSorted() {
        let names = ProgressQuestion.alphabetical.map(\.displayName)
        let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        XCTAssertEqual(names, sorted)
    }

    func testPersistedRawValuesRestoreSelection() {
        let suite = "ProgressQuestionSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for (raw, expected) in [("workoutHistory", ProgressQuestion.strengthOverTime),
                                ("observations", .observations),
                                ("bogus", .strengthOverTime)] {
            defaults.set(raw, forKey: ProgressQuestionSelection.persistenceKey)
            XCTAssertEqual(ProgressQuestionSelection.persisted(defaults: defaults).selected, expected)
        }
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

    func testOnlyWorkoutHistoryHostsItsOwnList() {
        XCTAssertEqual(ProgressQuestion.allCases.filter(\.hostsOwnList), [.workoutHistory])
    }

    func testSelectingHistoryKeepsPickerStateStable() {
        var selection = ProgressQuestionSelection(selected: .tests)
        selection.select(.workoutHistory)
        XCTAssertEqual(selection.selected, .strengthOverTime)
        selection.select(.tests)
        XCTAssertEqual(selection.selected, .tests)
    }
}
