import XCTest
import CadenceCore
@testable import CadenceFeatures

final class HomeWorkoutStartChoiceTests: XCTestCase {
    func testStrengthChoicesAndRecentCardioLimit() {
        XCTAssertEqual(HomeStrengthStartChoice.allCases.map(\.title), ["Quick Start", "Suggested", "Previous"])
        XCTAssertEqual(HomeRecentCardioChoices.recent(["run", "run", "walk", "cycle", "swim"]),
                       ["run", "walk", "cycle"])
        XCTAssertEqual(HomeRecentCardioChoices.recent([String]()), [])
    }
    func testUnifiedPhoneAndWatchChoicesIncludeEveryWorkoutOnce() {
        let choices = HomeWorkoutStartChoice.allChoices
        XCTAssertEqual(choices.map(\.title), [
            "Suggested Strength", "Previous Strength", "Custom Strength", "HIIT",
            "Run", "Walk", "Cycle", "Rowing", "Swim", "Elliptical", "Stairs", "Boxing", "Custom Cardio"
        ])
        XCTAssertEqual(Set(choices.map(\.id)).count, choices.count)
        for type in WorkoutType.allCases where type != .weights {
            XCTAssertTrue(choices.contains(.cardio(type)))
        }
        XCTAssertFalse(choices.contains(.cardio(.weights)))
        XCTAssertTrue(choices.allSatisfy { !$0.symbol.isEmpty })
    }

}
