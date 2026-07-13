import XCTest

/// Smoke: record a fitness test from the Tests tab and see it land in the log.
/// Assessment math is unit-tested in CadenceCore; this proves the record flow.
/// Replaces P4AssessmentsUITests / CoachTestRecommendationUITests.
final class SmokeAssessmentTests: CadenceUITestCase {
    func testRecordAssessmentShowsInFitness() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.tabBars.buttons["Tests"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Tests"].tap()

        app.descendants(matching: .any)["tests.assessment.pushupMax"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["assessment.record"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["assessment.record"].firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["record.assessment.save"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["record.assessment.save"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["10 reps"].waitForExistence(timeout: 5),
                      "the recorded result should appear in the series log")
    }
}
