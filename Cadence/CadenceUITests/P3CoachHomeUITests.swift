import XCTest

/// strength-pivot P3 — the bottom tab bar (Workout/Tests/Progress), the Coach card on
/// Home with simplified Coach navigation, the Coach settings, and the redesigned
/// Home layout (quick-actions row, planned-rest-of-week card, Coach start button).
final class P3CoachHomeUITests: CadenceUITestCase {

    func testTabBarHasThreeTabs() {
        let app = XCUIApplication.launched()

        // All three tabs are present.
        XCTAssertTrue(app.tabBars.buttons["Workout"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Tests"].exists)
        XCTAssertTrue(app.tabBars.buttons["Progress"].exists)

        // Tests is the assessments hub.
        app.tabBars.buttons["Tests"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["tests.assessments.list"].waitForExistence(timeout: 5))

        // Progress is the training history.
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["progress"].waitForExistence(timeout: 5))

        // Back to Workout = the Home dashboard with its Coach card.
        app.tabBars.buttons["Workout"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 5))
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

    // MARK: Home redesign — quick-actions row, plan card, Coach start button

    func testCoachCardHasStartButton() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))
        // The green Start button now lives inside the Coach card.
        XCTAssertTrue(app.buttons["home.coachStart"].exists,
                      "Coach card should contain the Start button")
    }

    func testQuickActionsRowHasAllFourChips() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 10),
                      "Strength quick-action chip")
        XCTAssertTrue(app.buttons["home.startCardio"].exists, "Cardio quick-action chip")
        XCTAssertTrue(app.buttons["home.logWorkout"].exists, "Log quick-action chip")
        XCTAssertTrue(app.buttons["home.planning"].exists, "Programs quick-action chip")
    }

    func testQuickActionStrengthOpensWeightsStart() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.startWorkout"), "Strength chip")
        XCTAssertTrue(app.buttons["weights.quickStart"].waitForExistence(timeout: 10),
                      "should open the Strength start screen")
    }

    func testQuickActionCardioOpensPicker() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.startCardio"), "Cardio chip")
        XCTAssertTrue(app.buttons["startType.run"].waitForExistence(timeout: 10),
                      "cardio-only picker should open")
    }

    func testQuickActionLogOpensPicker() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.logWorkout"), "Log chip")
        // The log picker offers both strength and cardio log options.
        XCTAssertTrue(app.buttons["logType.strength"].waitForExistence(timeout: 10)
                      || app.buttons["logType.other"].waitForExistence(timeout: 10),
                      "log picker should open")
    }

    func testQuickActionProgramsNavigates() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.planning"), "Programs chip")
        // Should navigate to the programs/routines planning surface.
        XCTAssertTrue(app.descendants(matching: .any)["planning"].waitForExistence(timeout: 10),
                      "should navigate to Programs & Routines")
    }

    // MARK: - Header date

    func testHomeHeaderShowsDate() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.descendants(matching: .any)["home.headerDate"].waitForExistence(timeout: 10),
                      "header date should appear beneath the title")
    }

    // MARK: - Coach completed/on-plan state

    func testCoachShowsCompleteBannerAfterWednesdayBoxing() {
        let app = XCUIApplication.launched(seeds: ["coachWednesdayComplete"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        // Coach should show the "Plan followed" completion banner, not the Start button
        let completeBanner = app.buttons["coach.card.completeBanner"]
        XCTAssertTrue(completeBanner.waitForExistence(timeout: 10),
                      "Coach should show complete banner after Wednesday boxing")
        XCTAssertTrue(completeBanner.label.contains("Plan followed"),
                      "Complete banner should say 'Plan followed'")

        // Start button should NOT be visible when plan is complete
        XCTAssertFalse(app.buttons["home.coachStart"].exists,
                       "Start button must not appear when today's plan is already complete")
    }

    // MARK: - Planned rest of week

    func testHomeShowsPlannedRestOfWeekAndYourPlanLink() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.descendants(matching: .any)["home.plannedRestOfWeek"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home.yourPlan"].exists)
        app.buttons["home.yourPlan"].tap()
        XCTAssertTrue(app.navigationBars["Your Plan"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Planned (rest of week)"].exists)
    }

    // MARK: - Settings schedule preferences link

    func testSettingsLinksToCoachSchedulePreferences() {
        let app = XCUIApplication.launched()
        app.buttons["home.settings"].tap()

        // Scroll to the Coach section at the bottom of Settings
        let link = app.buttons["settings.coach.schedulePreferences"]
        if !link.exists || !link.isHittable {
            app.swipeUp()
            app.swipeUp()
        }
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.navigationBars["Coach preferences"].waitForExistence(timeout: 5))
    }
}
