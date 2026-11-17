import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchHomeWorkoutSelectionTests: XCTestCase {
    func testStrengthIsDefaultWithWatchSpecificNamesAndIcons() {
        let state = WatchHomeWorkoutSelection()
        XCTAssertEqual(state.mode, .strength)
        XCTAssertEqual(state.choices.map { state.title(for: $0) }, ["Personalized", "Previous", "Custom"])
        XCTAssertEqual(Set(state.choices.map(\.symbol)), ["dumbbell.fill"])
        XCTAssertNil(state.launchChoice)
    }

    func testSelectingAndSwitchingModesNeverLaunches() {
        var state = WatchHomeWorkoutSelection()
        for choice in state.choices {
            state.select(choice)
            XCTAssertNil(state.launchChoice)
        }
        state.show(.cardio)
        XCTAssertEqual(Set(state.choices), Set(HomeWorkoutStartChoice.cardioChoices))
        for choice in state.choices {
            state.select(choice)
            XCTAssertNil(state.launchChoice)
        }
        state.show(.strength)
        XCTAssertEqual(state.selection, .strength(.quickStart))
        XCTAssertNil(state.launchChoice)
    }

    func testStartSnapshotsSelectionUntilDismissed() {
        var state = WatchHomeWorkoutSelection()
        state.select(.strength(.previous))
        state.start()
        XCTAssertEqual(state.launchChoice, .strength(.previous))
        state.show(.cardio)
        state.select(.cardio(.swim))
        XCTAssertEqual(state.launchChoice, .strength(.previous))
        state.dismissStart()
        XCTAssertNil(state.launchChoice)
        state.start()
        XCTAssertEqual(state.launchChoice, .cardio(.swim))
    }

    func testEachModeRestoresItsOwnChoiceAndAlwaysOpensOnStrength() throws {
        let suite = "WatchHomeWorkoutSelectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var state = WatchHomeWorkoutSelection.persisted(defaults: defaults)
        state.select(.strength(.previous))
        state.show(.cardio)
        state.select(.cardio(.rowing))
        state.persist(defaults: defaults)
        var restored = WatchHomeWorkoutSelection.persisted(defaults: defaults)
        XCTAssertEqual(restored.mode, .strength)
        XCTAssertEqual(restored.selection, .strength(.previous))
        restored.show(.cardio)
        XCTAssertEqual(restored.selection, .cardio(.rowing))
        XCTAssertNil(restored.launchChoice)
        XCTAssertNil(defaults.string(forKey: HomeWorkoutStartChoice.selectionStorageKey))
    }

    func testInvalidCrossModeChoicesAndLegacyPreferencesRestoreSafely() {
        var invalid = WatchHomeWorkoutSelection(savedStrengthID: "cardio.swim", savedCardioID: "strength.previous")
        XCTAssertEqual(invalid.selection, .strength(.suggested))
        invalid.select(.cardio(.run))
        XCTAssertEqual(invalid.selection, .strength(.suggested))
        invalid.show(.cardio)
        XCTAssertEqual(invalid.selection, .cardio(.hiit))
        let legacy = WatchHomeWorkoutSelection(legacyChoiceID: "strength.previous")
        XCTAssertEqual(legacy.selection, .strength(.previous))
    }
}
