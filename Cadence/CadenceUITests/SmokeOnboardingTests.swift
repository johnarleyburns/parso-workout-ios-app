import XCTest

/// Smoke: the first-run onboarding surface renders and reaches Home. The 4-screen
/// state machine itself is unit-tested in `OnboardingModelTests` (test-pyramid
/// Phase 4); this only proves it presents and dismisses on-device. Replaces the
/// 9-test OnboardingUITests.
final class SmokeOnboardingTests: CadenceUITestCase {
    func testFirstRunShowsOnboardingAndReachesHome() {
        let app = XCUIApplication.launched(extraArgs: ["-showOnboarding"])
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 15),
                      "onboarding should present on first run")

        // Advance one page to exercise navigation, then skip to Home.
        app.buttons["onboarding.primary"].tap()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitTap(), "skip onboarding")

        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 15),
                      "Home should appear after onboarding")
    }
}
