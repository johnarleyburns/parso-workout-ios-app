import XCTest
@testable import CadenceFeatures

final class WatchStrengthSettingsTests: XCTestCase {
    func testPopularRepPatternsIncludeCommonStrengthAndHypertrophyChoices() {
        let ids = WatchRepPattern.popular.map(\.id)

        XCTAssertTrue(ids.contains("12-10-8"))
        XCTAssertTrue(ids.contains("12-10-8-6"))
        XCTAssertTrue(ids.contains("5-5-5"))
    }

    func testRepPatternNormalizationFallsBackToDefault() {
        XCTAssertEqual(WatchRepPattern.normalized([]), .fallback)
        XCTAssertEqual(WatchRepPattern.normalized([12, 10, 8]).id, "12-10-8")
    }

    func testRestOptionsNormalizeToPopularChoices() {
        XCTAssertEqual(WatchRestOptions.popular, [20, 30, 60, 90])
        XCTAssertEqual(WatchRestOptions.normalized(90), 90)
        XCTAssertEqual(WatchRestOptions.normalized(45), 60)
    }

    func testRIRConvertsToStoredRPE() {
        XCTAssertEqual(WatchEffortMode.rir.rpeValue(from: 2), 8)
        XCTAssertEqual(WatchEffortMode.rpe.rpeValue(from: 9), 9)
        XCTAssertNil(WatchEffortMode.rpe.rpeValue(from: nil))
    }
}
