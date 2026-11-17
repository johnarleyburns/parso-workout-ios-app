import XCTest
import CadenceCore
@testable import CadenceFeatures

final class HomeWorkoutStartChoiceTests: XCTestCase {
    func testStrengthChoicesAndRecentCardioLimit() {
        XCTAssertEqual(HomeStrengthStartChoice.allCases.map(\.title), ["Quick Start", "Personalized", "Previous"])
        XCTAssertEqual(HomeRecentCardioChoices.recent(["run", "run", "walk", "cycle", "swim"]),
                       ["run", "walk", "cycle"])
        XCTAssertEqual(HomeRecentCardioChoices.recent([String]()), [])
    }
    func testUnifiedPhoneAndWatchChoicesIncludeEveryWorkoutOnce() {
        let choices = HomeWorkoutStartChoice.allChoices
        XCTAssertEqual(choices.map(\.title), [
            "Optimal Lifts", "Repeat Lifts", "Quick Start", "HIIT",
            "Run", "Walk", "Cycle", "Rowing", "Swim", "Elliptical", "Stairs", "Boxing", "Custom Cardio"
        ])
        XCTAssertEqual(Set(choices.map(\.id)).count, choices.count)
        for type in WorkoutType.allCases where type != .weights {
            XCTAssertTrue(choices.contains(.cardio(type)))
        }
        XCTAssertFalse(choices.contains(.cardio(.weights)))
        XCTAssertEqual(Set(HomeWorkoutStartChoice.strengthChoices.map(\.symbol)), ["dumbbell.fill"])
        XCTAssertTrue(choices.allSatisfy { !$0.symbol.isEmpty })
    }

    func testEveryChoiceRestoresFromPersistedSelection() throws {
        let suiteName = "HomeWorkoutStartChoiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = HomeWorkoutStartChoice.selectionStorageKey
        for choice in HomeWorkoutStartChoice.allChoices {
            defaults.set(choice.id, forKey: key)
            let reopened = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            let saved = try XCTUnwrap(reopened.string(forKey: key))
            XCTAssertEqual(HomeWorkoutStartChoice.restored(from: saved), choice)
        }
    }

    func testMissingOrObsoleteSelectionUsesSuggestedStrength() {
        for identifier in ["", "cardio.removedActivity", "strength.removedSource", "cardio.weights"] {
            XCTAssertEqual(HomeWorkoutStartChoice.restored(from: identifier), .strength(.suggested))
        }
    }

}
