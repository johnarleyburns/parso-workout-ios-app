import XCTest

/// P7 (issue 7) — the "Your Plan" redesign: TODAY-first section, strength tonnage,
/// and (with cardio history) an HR-zone breakdown. Also the optional age onboarding.
final class YourPlanRedesignUITests: CadenceUITestCase {

    /// Opens Your Plan via the week strip, scrolling it into view first. Uses the
    /// retry-based `tapToReveal` because the NavigationStack push can drop a single
    /// tap on a degraded simulator (pre-existing P3CoachHome flake).
    private func openYourPlan(_ app: XCUIApplication) {
        _ = app.scrollToHittableAndTap("home.yourPlan", maxSwipes: 12)
        if app.navigationBars["Your Plan"].waitForExistence(timeout: 6) { return }
        XCTAssertTrue(app.tapToReveal("home.yourPlan", "Your Plan"),
                      "Your Plan screen should open")
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

    /// Fix 8: the HR-zone breakdown renders a stacked zone bar and a resolved
    /// science link (no raw citation id like "seilerPolarized2010" or
    /// "tanakaMaxHR2001" visible to the user).
    func testYourPlanShowsZoneBarAndResolvedScienceLink() {
        let app = XCUIApplication.launched(seeds: ["coachWednesdayComplete"])
        openYourPlan(app)

        // Scroll the stacked zone bar into view.
        let bar = app.descendants(matching: .any)["yourPlan.zoneBar"]
        var found = bar.waitForExistence(timeout: 3)
        for _ in 0..<10 where !found { app.swipeUp(); found = bar.exists }
        XCTAssertTrue(found, "Your Plan should render the stacked HR-zone bar")

        // No raw citation id should ever be visible to the user.
        XCTAssertFalse(app.staticTexts["seilerPolarized2010"].exists,
                       "raw citation id must never be shown")
        XCTAssertFalse(app.staticTexts["tanakaMaxHR2001"].exists,
                       "the old max-HR citation id must not appear")
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
