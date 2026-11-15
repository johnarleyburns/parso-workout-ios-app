import XCTest
@testable import CadenceFeatures

final class HomeWorkoutStartChoiceTests: XCTestCase {
    func testStrengthChoicesAndRecentCardioLimit() {
        XCTAssertEqual(HomeStrengthStartChoice.allCases.map(\.title), ["Quick Start", "Suggested", "Previous"])
        XCTAssertEqual(HomeRecentCardioChoices.recent(["run", "run", "walk", "cycle", "swim"]),
                       ["run", "walk", "cycle"])
        XCTAssertEqual(HomeRecentCardioChoices.recent([String]()), [])
    }
}
