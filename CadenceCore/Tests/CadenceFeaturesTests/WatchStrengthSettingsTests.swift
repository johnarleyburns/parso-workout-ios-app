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

    func testCustomStrengthDefaultsRestoreLastRepRestAndPartners() {
        let defaults = WatchCustomStrengthDefaults(
            storedRepPattern: "5-5-5",
            storedRestSeconds: 90,
            storedPartners: "Sam\nAlex",
            recentPartners: ["Alex", "Jo"]
        )

        XCTAssertEqual(defaults.repPattern.id, "5-5-5")
        XCTAssertEqual(defaults.restSeconds, 90)
        XCTAssertEqual(defaults.selectedPartners, ["Sam", "Alex"])
        XCTAssertEqual(defaults.partnerOptions, ["Sam", "Alex", "Jo"])
    }

    func testCustomStrengthDefaultsPreserveSoloLastWorkout() {
        let defaults = WatchCustomStrengthDefaults(
            storedRepPattern: "12-10-8-6",
            storedRestSeconds: 20,
            storedPartners: "",
            recentPartners: ["Sam"]
        )

        XCTAssertEqual(defaults.repPattern.id, "12-10-8-6")
        XCTAssertEqual(defaults.restSeconds, 20)
        XCTAssertEqual(defaults.selectedPartners, [])
        XCTAssertEqual(defaults.partnerOptions, ["Sam"])
    }

    func testExerciseSearchPresenterShowsSpinnerWhileSearchIsOngoing() {
        XCTAssertEqual(
            WatchExerciseSearchPresenter.phase(query: "bench", isSearching: true, resultCount: 0),
            .searching
        )
        XCTAssertEqual(
            WatchExerciseSearchPresenter.phase(query: "bench", isSearching: true, resultCount: 3),
            .searching,
            "An in-flight query should show progress instead of stale results."
        )
        XCTAssertEqual(
            WatchExerciseSearchPresenter.phase(query: "bench", isSearching: false, resultCount: 0),
            .noMatches
        )
    }

    func testPlateIncrementsUseCommonPoundAndKilogramPlates() {
        XCTAssertEqual(WeightIncrement(unit: .pounds).positiveChips, [45, 35, 25, 10, 5, 2.5])
        XCTAssertEqual(WeightIncrement(unit: .pounds).negativeChips, [-45, -35, -25, -10, -5, -2.5])
        XCTAssertEqual(WeightIncrement(unit: .kilograms).positiveChips, [25, 20, 15, 10, 5, 2.5])
        XCTAssertEqual(WeightIncrement(unit: .kilograms).negativeChips, [-25, -20, -15, -10, -5, -2.5])
        XCTAssertEqual(WeightIncrement(unit: .pounds).crownDetent, 2.5)
    }

    func testRIRConvertsToStoredRPE() {
        XCTAssertEqual(WatchEffortMode.rir.rpeValue(from: 2), 8)
        XCTAssertEqual(WatchEffortMode.rpe.rpeValue(from: 9), 9)
        XCTAssertNil(WatchEffortMode.rpe.rpeValue(from: nil))
    }
}
