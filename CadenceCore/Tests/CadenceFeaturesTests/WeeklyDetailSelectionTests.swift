import XCTest
@testable import CadenceFeatures

final class WeeklyDetailSelectionTests: XCTestCase {
    func testWeeklyDetailsCanBeExpandedIndependently() {
        var selection = WeeklyDetailSelection()

        selection.toggle(.strength)
        XCTAssertTrue(selection.isExpanded(.muscleMap))
        XCTAssertTrue(selection.isExpanded(.strength))

        selection.toggle(.cardio)
        XCTAssertTrue(selection.isExpanded(.cardio))
        XCTAssertTrue(selection.isExpanded(.strength))

        selection.toggle(.muscleMap)
        XCTAssertFalse(selection.isExpanded(.muscleMap))
        XCTAssertTrue(selection.isExpanded(.muscleGroupVolume) == false)
    }

    func testSelectingAWeeklyDetailDoesNotCollapseOtherDetails() {
        var selection = WeeklyDetailSelection(expanded: [.muscleGroupVolume])

        selection.select(.cardio)
        XCTAssertTrue(selection.isExpanded(.muscleGroupVolume))
        XCTAssertTrue(selection.isExpanded(.cardio))

        selection.select(.cardio)
        XCTAssertTrue(selection.isExpanded(.cardio))
    }

    func testTogglingExpandedWeeklyDetailCollapsesOnlyThatDetail() {
        var selection = WeeklyDetailSelection(expanded: [.muscleMap, .strength])

        selection.toggle(.muscleMap)

        XCTAssertFalse(selection.isExpanded(.muscleMap))
        XCTAssertTrue(selection.isExpanded(.strength))
    }

    func testFreshSelectionExpandsTheMuscleMapOnly() {
        let selection = WeeklyDetailSelection()

        XCTAssertTrue(selection.isExpanded(.muscleMap))
        XCTAssertFalse(selection.isExpanded(.muscleGroupVolume))
        XCTAssertFalse(selection.isExpanded(.strength))
        XCTAssertFalse(selection.isExpanded(.cardio))
    }

    func testPersistedSelectionRoundTripsIndependentExpansion() {
        let suiteName = "WeeklyDetailSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let original = WeeklyDetailSelection(expanded: [.muscleGroupVolume, .cardio])
        original.persist(defaults: defaults)

        XCTAssertEqual(WeeklyDetailSelection.persisted(defaults: defaults), original)
    }

    func testPersistedSelectionIgnoresUnknownModes() {
        let suiteName = "WeeklyDetailSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(["muscleMap", "not-a-real-section"],
                     forKey: WeeklyDetailSelection.persistenceKey)

        XCTAssertEqual(WeeklyDetailSelection.persisted(defaults: defaults).expanded,
                       [.muscleMap])
    }
}
