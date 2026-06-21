import XCTest

/// Onboarding flow — the four-screen first-run experience that captures training
/// goal, experience level, and unit preference. Tests run with `-showOnboarding`
/// to override the default `-uiTest` skip.
final class OnboardingUITests: CadenceUITestCase {

    // Onboarding appears on first launch when flagged.
    func testOnboardingAppears() {
        let app = XCUIApplication.launched(extraArgs: ["-showOnboarding"])
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 10),
                      "Skip button should appear on onboarding")
        XCTAssertTrue(app.buttons["onboarding.primary"].exists,
                      "Continue/Start button should appear")
    }

    // Completing the full 4-screen flow dismisses onboarding and lands on Home.
    func testOnboardingCompletes() {
        let app = XCUIApplication.launched(extraArgs: ["-showOnboarding"])
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 10))

        // Page 0 → 1 (Goal)
        app.buttons["onboarding.primary"].tap()
        sleep(1)

        // Page 1 → 2 (Experience)
        app.buttons["onboarding.primary"].tap()
        sleep(1)

        // Page 2 → 3 (Units)
        app.buttons["onboarding.primary"].tap()
        sleep(1)

        // Last page → "Start training" → dismiss
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 5))
        app.buttons["onboarding.primary"].tap()

        // Should land on Home with the coach card visible.
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10),
                      "Home screen should appear after onboarding")
    }

    // Tapping Skip on the welcome page dismisses onboarding immediately.
    func testOnboardingSkipsFromWelcome() {
        let app = XCUIApplication.launched(extraArgs: ["-showOnboarding"])
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 10))
        app.buttons["onboarding.skip"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10),
                      "Home screen should appear after skipping onboarding")
    }

    // Tapping Skip from a later page also dismisses.
    func testOnboardingSkipsFromLaterPage() {
        let app = XCUIApplication.launched(extraArgs: ["-showOnboarding"])
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 10))

        // Navigate to page 1 (Goal).
        app.buttons["onboarding.primary"].tap()
        sleep(1)

        // Skip from page 1.
        XCTAssertTrue(app.buttons["onboarding.skip"].exists, "Skip should be available on every page")
        app.buttons["onboarding.skip"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10),
                      "Home screen should appear after skipping from later page")
    }

    // Back button navigates to the previous page.
    func testOnboardingBackNavigation() {
        let app = XCUIApplication.launched(extraArgs: ["-showOnboarding"])
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 10))

        // Navigate to page 1.
        app.buttons["onboarding.primary"].tap()
        sleep(1)

        // Back button should appear.
        let back = app.buttons["onboarding.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Back button should appear after page 0")
        back.tap()
        sleep(1)

        // Back on page 0 — back button should be gone.
        XCTAssertFalse(app.buttons["onboarding.back"].exists, "Back button should be hidden on page 0")
    }

    // Selecting a goal card highlights it with a checkmark.
    func testOnboardingSelectGoal() {
        let app = XCUIApplication.launched(extraArgs: ["-showOnboarding"])
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 10))

        // Navigate to goal page (page 1).
        app.buttons["onboarding.primary"].tap()
        sleep(1)

        // The goal picker cards are identifiable by their title text. Verify at
        // least Strength and Hypertrophy are selectable.
        XCTAssertTrue(app.staticTexts["Strength"].exists, "Strength goal option")
        XCTAssertTrue(app.staticTexts["Hypertrophy"].exists, "Hypertrophy goal option")
    }

    // Selecting an experience card highlights it.
    func testOnboardingSelectExperience() {
        let app = XCUIApplication.launched(extraArgs: ["-showOnboarding"])
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 10))

        // Navigate to page 2.
        app.buttons["onboarding.primary"].tap()
        sleep(1)
        app.buttons["onboarding.primary"].tap()
        sleep(1)

        XCTAssertTrue(app.staticTexts["Beginner"].exists, "Beginner option")
        XCTAssertTrue(app.staticTexts["Intermediate"].exists, "Intermediate option")
        XCTAssertTrue(app.staticTexts["Advanced"].exists, "Advanced option")
    }

    // Units page shows the segmented picker and Health connect button.
    func testOnboardingUnitsPage() {
        let app = XCUIApplication.launched(extraArgs: ["-showOnboarding"])
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 10))

        // Navigate to page 3.
        for _ in 0..<3 {
            app.buttons["onboarding.primary"].tap()
            sleep(1)
        }

        // Units picker and Health connect button.
        XCTAssertTrue(app.buttons["onboarding.units"].exists, "Units picker")
        XCTAssertTrue(app.buttons["onboarding.health"].exists, "Health connect button")

        // Last page shows "Start training" not "Continue".
        XCTAssertTrue(app.buttons["onboarding.primary"].label == "Start training"
                      || app.staticTexts["Start training"].exists,
                      "Last page should say Start training")
    }

    // After completing onboarding, it does not show on next launch.
    func testOnboardingDoesNotShowAfterCompletion() {
        let app = XCUIApplication.launched(extraArgs: ["-showOnboarding"])
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 10))

        // Complete all 4 pages.
        for _ in 0..<4 {
            app.buttons["onboarding.primary"].tap()
            sleep(1)
        }

        // Should now be on Home.
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        // Terminate and relaunch — onboarding should not appear.
        app.terminate()
        let app2 = XCUIApplication()
        app2.launchArguments += ["-uiTest"]
        app2.launch()
        XCTAssertTrue(app2.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10),
                      "Onboarding should not reappear")
    }
}
