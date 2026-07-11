import XCTest

/// P7 (issue 7) — the "Your Plan" redesign: TODAY-first section, strength tonnage,
/// and (with cardio history) an HR-zone breakdown. Also the optional age onboarding.
final class YourPlanRedesignUITests: CadenceUITestCase {

    /// Opens Your Plan via the week strip, scrolling it into view first.
    private func openYourPlan(_ app: XCUIApplication) {
        XCTAssertTrue(app.scrollToHittableAndTap("home.yourPlan", maxSwipes: 12), "open Your Plan")
        XCTAssertTrue(app.navigationBars["Your Plan"].waitForExistence(timeout: 10), "Your Plan screen")
    }

    func testYourPlanShowsTodayFirstAndTonnage() {
        // This seed logs strength + cardio in the current week, so tonnage > 0.
        let app = XCUIApplication.launched(seeds: ["coachWednesdayComplete"])
        openYourPlan(app)

        // TODAY-first section.
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5)
                      || app.descendants(matching: .any)["yourPlan.today"].waitForExistence(timeout: 5),
                      "Your Plan should lead with a Today section")

        // Strength tonnage row.
        let tonnage = app.descendants(matching: .any)["yourPlan.tonnage"]
        var found = tonnage.waitForExistence(timeout: 3)
        for _ in 0..<8 where !found { app.swipeUp(); found = tonnage.exists }
        XCTAssertTrue(found, "Your Plan should show strength tonnage")
    }

    func testYourPlanShowsHRZonesWithCardioHistory() {
        // coachWednesdayComplete logs boxing + a run in the current week.
        let app = XCUIApplication.launched(seeds: ["coachWednesdayComplete"])
        openYourPlan(app)

        // Scroll to find the HR-zone breakdown (any Z1..Z5 row).
        var found = false
        for _ in 0..<10 {
            for z in 1...5 where app.descendants(matching: .any)["yourPlan.zone.\(z)"].exists {
                found = true; break
            }
            if found { break }
            app.swipeUp()
        }
        XCTAssertTrue(found, "Your Plan should show a cardio HR-zone breakdown with cardio history")
    }

    func testOnboardingHasOptionalAgeField() {
        let app = XCUIApplication.launched(extraArgs: ["-showOnboarding"])
        // Advance to the units/age page.
        for _ in 0..<5 {
            if app.descendants(matching: .any)["onboarding.age"].exists { break }
            let next = app.buttons["onboarding.primary"]
            if next.waitForExistence(timeout: 5) { next.tap() }
        }
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.age"].waitForExistence(timeout: 5),
                      "Onboarding should collect an optional age for HR-zone estimation")
    }
}
