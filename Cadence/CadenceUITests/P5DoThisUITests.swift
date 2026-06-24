import XCTest

/// strength-pivot P5.3, updated for the Coach Start routing contract
/// (audio/coach routing plan §D): a strength Coach recommendation opens the
/// workout's PLAN EDITOR first — the user reviews/edits the prescribed movements,
/// then taps the editor's Start to begin. Coach Start never drops the user
/// straight into an active session.
final class P5DoThisUITests: CadenceUITestCase {

    /// Coach Start for a strength recommendation lands on the plan editor (setup),
    /// not an active logging session.
    func testCoachStrengthStartOpensSetupFirst() {
        let app = XCUIApplication.launched(seeds: ["coachStrengthPrimary"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.scrollToHittableAndTap("home.coachStart"), "tap Coach Start")
        XCTAssertTrue(app.buttons["editor.start"].waitForExistence(timeout: 10),
                      "the plan editor (setup) should open first")
        XCTAssertFalse(app.buttons["session.addExercise"].exists,
                       "no active session should exist before confirming from setup")
    }

    /// The Coach card itself never materializes an active session — the editor is
    /// the gate. (The editor's own Start → warm-up → logger plumbing is pre-existing
    /// and covered by the strength-logging suite.)
    func testCoachCardNeverOpensActiveSessionDirectly() {
        let app = XCUIApplication.launched(seeds: ["coachStrengthPrimary"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.scrollToHittableAndTap("home.coachStart"), "tap Coach Start")
        // We are in setup (editor), not an active session.
        XCTAssertTrue(app.buttons["editor.start"].waitForExistence(timeout: 10), "plan editor opens")
        XCTAssertFalse(app.staticTexts["session.elapsed"].exists, "no active session timer")
        XCTAssertFalse(app.staticTexts["record.elapsed"].exists, "no active recorder")
    }
}
