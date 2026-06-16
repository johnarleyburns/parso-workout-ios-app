import XCTest

/// strength-pivot P3 — the bottom tab bar (Workout/Plan/Library), the Coach card on
/// Home with its cited "why / the science" expander, and the Coach settings.
final class P3CoachHomeUITests: CadenceUITestCase {

    func testTabBarHasThreeTabs() {
        let app = XCUIApplication.launched()

        // All three tabs are present.
        XCTAssertTrue(app.tabBars.buttons["Workout"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Plan"].exists)
        XCTAssertTrue(app.tabBars.buttons["Library"].exists)

        // Plan is the assessments hub (P4); Library is still a placeholder.
        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan.assessments.list"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["library.placeholder"].waitForExistence(timeout: 5))

        // Back to Workout = the Home dashboard with its Coach card.
        app.tabBars.buttons["Workout"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 5))
    }

    func testCoachCardShowsCitedInsight() {
        // Seeded history → the engine has real data, so the card shows an insight
        // (not the cold-start placeholder) with an expandable, cited rationale.
        let app = XCUIApplication.launched(seeds: ["history"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        // Expand "Why / the science" → the citation becomes visible (D3).
        let why = app.descendants(matching: .any)["coach.card.why"].firstMatch
        XCTAssertTrue(why.waitForExistence(timeout: 5))
        why.tap()
        XCTAssertTrue(app.descendants(matching: .any)["coach.card.citation"].firstMatch.waitForExistence(timeout: 5),
                      "citation should appear after expanding the science")
    }

    func testCoachSettingsPickersExist() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.settings"), "open Settings")

        // The Coach section is appended at the bottom of Settings — scroll to it.
        let goal = app.buttons["settings.coach.goal"]
        var found = goal.waitForExistence(timeout: 2)
        for _ in 0..<8 where !found {
            app.swipeUp()
            found = goal.exists
        }
        XCTAssertTrue(found, "Coach training-goal picker")
        XCTAssertTrue(app.buttons["settings.coach.experience"].exists, "Coach experience picker")
    }
}
