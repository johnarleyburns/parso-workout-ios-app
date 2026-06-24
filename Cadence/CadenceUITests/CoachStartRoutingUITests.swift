import XCTest

/// Coach Start routing (audio/coach routing plan §D): every trainable Coach
/// recommendation opens that workout's setup/settings surface first — never an
/// active recorder until the user confirms from the setup screen.
final class CoachStartRoutingUITests: CadenceUITestCase {

    /// Boxing conditioning → boxing interval SETUP (rounds stepper), not the
    /// generic Other-cardio recorder and not a running interval.
    func testCoachBoxingStartOpensBoxingSetup() {
        let app = XCUIApplication.launched(seeds: ["coachBoxingPrimary"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Boxing conditioning"].waitForExistence(timeout: 5),
                      "Coach primary should be Boxing conditioning")

        let cta = app.buttons["home.coachStart"]
        XCTAssertTrue(cta.waitForExistence(timeout: 5))
        XCTAssertEqual(cta.label, "Start", "Coach cardio CTA should read 'Start'")

        XCTAssertTrue(app.scrollToHittableAndTap("home.coachStart"), "tap Coach Start")

        XCTAssertTrue(app.descendants(matching: .any)["interval.custom.rounds"].waitForExistence(timeout: 10),
                      "boxing setup (rounds stepper) should appear")
        XCTAssertFalse(app.staticTexts["record.elapsed"].exists, "no active Other-cardio recorder")
        XCTAssertFalse(app.staticTexts["interval.countdown"].exists,
                       "interval must not be running before tapping Start in setup")
    }

    /// Run → the distance-goal chooser first, not an active outdoor recorder.
    func testCoachRunStartOpensGoalSetup() {
        let app = XCUIApplication.launched(seeds: ["coachRunPrimary"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.scrollToHittableAndTap("home.coachStart"), "tap Coach Start")

        XCTAssertTrue(app.buttons["goal.none"].waitForExistence(timeout: 10),
                      "run goal setup should appear")
        XCTAssertFalse(app.staticTexts["outdoor.elapsed"].exists, "no active outdoor recorder")
    }

    /// Strength → the plan editor first, not the active logger.
    func testCoachStrengthStartOpensWorkoutPlanEditor() {
        let app = XCUIApplication.launched(seeds: ["coachStrengthPrimary"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.scrollToHittableAndTap("home.coachStart"), "tap Coach Start")

        XCTAssertTrue(app.buttons["editor.start"].waitForExistence(timeout: 10),
                      "plan editor should appear")
        XCTAssertFalse(app.buttons["session.addExercise"].exists,
                       "no active session before tapping editor Start")
    }
}
