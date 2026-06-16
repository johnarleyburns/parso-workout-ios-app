import XCTest

/// strength-pivot P4 — the Plan-tab assessment battery: open a kind, read its
/// standardized protocol, record a result, and see it land in the longitudinal log.
final class P4AssessmentsUITests: CadenceUITestCase {

    func testPlanTabListsAssessmentBattery() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Plan"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["plan.assessments.list"].waitForExistence(timeout: 5))
        // Both arms of the battery surface their rows.
        XCTAssertTrue(app.descendants(matching: .any)["plan.assessment.pushupMax"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["plan.assessment.e1RM"].exists)
    }

    func testRecordBodyweightResultAppearsInLog() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Plan"].tap()

        // Open the max push-ups assessment → its protocol + (empty) history.
        app.descendants(matching: .any)["plan.assessment.pushupMax"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["assessment.protocol"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["assessment.empty"].exists,
                      "no results yet before recording")

        // Record a result (rep tests default the stepper to 10) and save.
        app.descendants(matching: .any)["assessment.record"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["record.assessment.save"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["record.assessment.save"].firstMatch.tap()

        // The saved result shows in the series log.
        XCTAssertTrue(app.staticTexts["10 reps"].waitForExistence(timeout: 5),
                      "recorded 10-rep result should appear in the log")
    }
}
