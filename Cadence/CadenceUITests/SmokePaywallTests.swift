import XCTest

/// Smoke: a locked (free) user reaches the paywall from the Coach preview, and it
/// exposes Restore (App Review requirement). Entitlement resolution is unit-tested
/// in CadenceCore; this proves the StoreKit-config binding presents. Replaces
/// MonetizationUITests.
final class SmokePaywallTests: CadenceUITestCase {
    func testLockedUserSeesPaywall() {
        let app = XCUIApplication.launched(extraArgs: ["-proLocked"])
        let unlock = app.buttons["coach.preview.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Unlock CTA missing")
        unlock.tap()

        XCTAssertTrue(app.otherElements["paywall"].waitForExistence(timeout: 10)
                      || app.staticTexts["Cladiron Pro"].waitForExistence(timeout: 10),
                      "paywall did not present")
        XCTAssertTrue(app.buttons["paywall.restore"].waitForExistence(timeout: 10),
                      "paywall must expose Restore Purchases")
    }
}
