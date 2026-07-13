import XCTest

/// Smoke: the NFR-2 accessibility gate — Home's primary controls are reachable and
/// carry VoiceOver-resolvable identities. New coverage the old suite lacked.
final class SmokeAccessibilityTests: CadenceUITestCase {
    func testHomeIsAccessible() {
        let app = XCUIApplication.launched()

        // The three tabs are labelled and hittable.
        for tab in ["Workout", "Tests", "Progress"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 15), "\(tab) tab missing")
            XCTAssertTrue(button.isHittable, "\(tab) tab not hittable")
        }

        // The Start Workout hero is present and hittable.
        XCTAssertTrue(app.scrollToHittableAndTap("home.startWorkout"),
                      "Start Workout hero should be reachable")
    }
}
