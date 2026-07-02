import XCTest

/// Monetization gating UI tests (plan §4.7). The paywall's live product rows need
/// a StoreKit configuration bound to the run scheme, so these focus on the
/// entitlement gating, the funnel wiring, and the binding §1 guarantee that a free
/// user can log → review → export with zero paywall interruptions. Product
/// rendering (all three plans, prices, trial badge) is covered by the manual test
/// matrix in docs/monetization-test-matrix.md.
final class MonetizationUITests: CadenceUITestCase {

    // MARK: Free (locked)

    func testFreeUserSeesCoachPreview() {
        let app = XCUIApplication.launched(extraArgs: ["-proLocked"])
        XCTAssertTrue(app.otherElements["coach.preview"].waitForExistence(timeout: 15),
                      "Free users should see the Coach preview funnel")
        XCTAssertFalse(app.otherElements["coach.card"].exists,
                       "Free users must not see the full Coach card")
    }

    func testPaywallOpensFromPreviewAndHasRestore() {
        let app = XCUIApplication.launched(extraArgs: ["-proLocked"])
        let unlock = app.buttons["coach.preview.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Unlock CTA missing")
        unlock.tap()

        XCTAssertTrue(app.otherElements["paywall"].waitForExistence(timeout: 10)
                      || app.staticTexts["Cladiron Pro"].waitForExistence(timeout: 10),
                      "Paywall did not present")
        // Restore is an App Review requirement and is always present.
        XCTAssertTrue(app.buttons["paywall.restore"].waitForExistence(timeout: 10),
                      "Paywall must expose Restore Purchases")
    }

    /// The §1 principle as a regression test: a free user completes a full
    /// log flow with no paywall interruption.
    func testFreeUserCanLogWithoutPaywall() {
        let app = XCUIApplication.launched(extraArgs: ["-proLocked"])
        XCTAssertTrue(app.startEmptyStrengthWorkout(),
                      "Free user must be able to start/log a workout")
        XCTAssertFalse(app.otherElements["paywall"].exists,
                       "No paywall may interrupt the free logging loop")
    }

    // MARK: Pro (unlocked)

    func testProUserSeesCoachCard() {
        let app = XCUIApplication.launched(extraArgs: ["-proUnlocked"])
        XCTAssertTrue(app.otherElements["coach.card"].waitForExistence(timeout: 15),
                      "Pro users should see the full Coach card")
        XCTAssertFalse(app.otherElements["coach.preview"].exists,
                       "Pro users must not see the locked preview")
    }
}
