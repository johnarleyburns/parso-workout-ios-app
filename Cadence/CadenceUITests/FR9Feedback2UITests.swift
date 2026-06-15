import XCTest

/// Round 4 Part B field-test feedback batch 2 — the Weights start screen
/// (Quick Start / Start from Library, feedback #1) and the Swimming recorder
/// (feedback #3).
final class FR9Feedback2UITests: CadenceUITestCase {

    private func openWeights(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["startType.weights"].waitTap(), "Weights")
    }

    // #1 — Quick Start opens a blank session.
    func testWeightsQuickStartOpensSession() {
        let app = XCUIApplication.launched()
        openWeights(app)
        XCTAssertTrue(app.buttons["weights.quickStart"].waitTap(), "Quick Start")
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25),
                      "Quick Start opens a blank session")
    }

    // #1 — Start from Library launches a preset with its movements pre-loaded.
    func testWeightsLibraryStartsPreset() {
        let app = XCUIApplication.launched()
        openWeights(app)
        // 5×5 split into weekly days in feedback batch 3 (preset-5x5-1a…2b).
        XCTAssertTrue(app.buttons["weights.library.preset-5x5-1a"].waitTap(), "5×5 preset")
        XCTAssertTrue(app.buttons["plan.preview.start"].waitTap(), "Start preset")
        XCTAssertTrue(app.staticTexts["session.rx.Back Squat"].waitForExistence(timeout: 25),
                      "the preset's Back Squat should be pre-loaded as a planned card")
    }

    // #3 — Swimming records time + laps and shows them in the summary.
    func testSwimmingRecordsLaps() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["startType.swim"].waitTap(), "Swim")
        XCTAssertTrue(app.buttons["swim.start"].waitTap(), "Start swim")
        XCTAssertTrue(app.buttons["swim.lapPlus"].waitTap(), "lap +")
        app.buttons["swim.lapPlus"].tap()
        XCTAssertTrue(app.buttons["swim.end"].waitTap(), "End swim")
        XCTAssertTrue(app.staticTexts["summary.metric.laps"].waitForExistence(timeout: 25),
                      "swim summary shows laps")
    }
}
