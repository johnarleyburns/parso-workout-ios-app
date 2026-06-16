import XCTest

/// The About screen (reached from Settings) — product principles/methodology and a
/// link to the online privacy policy.
final class AboutUITests: CadenceUITestCase {

    func testAboutReachableFromSettingsWithPrivacyLink() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.settings"), "open Settings")

        // The About row is appended at the bottom of Settings — scroll to it.
        let about = app.buttons["settings.about"]
        var found = about.waitForExistence(timeout: 2)
        for _ in 0..<10 where !found {
            app.swipeUp()
            found = about.exists
        }
        XCTAssertTrue(found, "About row in Settings")
        about.tap()

        // The About page shows the product name and the privacy-policy link.
        XCTAssertTrue(app.descendants(matching: .any)["about.title"].waitForExistence(timeout: 5),
                      "About page title")
        XCTAssertTrue(app.descendants(matching: .any)["about.privacyLink"].firstMatch.exists,
                      "online privacy policy link")
        XCTAssertTrue(app.descendants(matching: .any)["about.sourceLink"].firstMatch.exists,
                      "open-source link")
    }
}
