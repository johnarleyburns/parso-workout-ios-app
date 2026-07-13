import XCTest

/// Smoke: a strength Coach recommendation opens the plan editor first — never a
/// live recorder. The routing *decision* is exhaustively unit-tested in
/// `CoachRouterTests` (Phase 4); this proves the on-device wiring. Replaces
/// P5DoThisUITests / CoachStartRoutingUITests / CoachSurfaceUITests /
/// AdditionalStrengthUITests.
final class SmokeCoachRoutingTests: CadenceUITestCase {
    func testCoachRecOpensPlanEditorNotRecorder() {
        let app = XCUIApplication.launched(seeds: ["coachStrengthPrimary"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 15))

        XCTAssertTrue(app.scrollToHittableAndTap("home.coachStart"), "tap Coach Start")
        XCTAssertTrue(app.buttons["editor.start"].waitForExistence(timeout: 10),
                      "the plan editor should open first")
        XCTAssertFalse(app.buttons["session.addExercise"].exists,
                       "no active session before confirming from setup")
    }
}
