import XCTest

/// strength-pivot P3 — the bottom tab bar (Workout/Tests/Progress), the Coach card on
/// Home with its cited "why / the science" expander, the Coach settings, and the
/// redesigned Home layout (quick-actions row, this-week card, Coach start button).
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

    func testCoachCardShowsPrescriptiveTarget() {
        // strength-pivot P5.2 — the card now leads with a prescription: a concrete
        // action + a loggable set/rep/load/RIR target, still cited (D3). Works even
        // at cold start (the engine returns a starter), but seed history for realism.
        let app = XCUIApplication.launched(seeds: ["history"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        // The structured target chip and the imperative action are both present.
        XCTAssertTrue(app.descendants(matching: .any)["coach.card.target"].firstMatch.waitForExistence(timeout: 5),
                      "the card should show a concrete loggable target")
        XCTAssertTrue(app.descendants(matching: .any)["coach.card.action"].firstMatch.exists,
                      "the card should show the prescribed action")

        // The cited rationale still expands from the prescription (D3).
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

    // MARK: Home redesign — quick-actions row, this-week card, Coach start button

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
        XCTAssertTrue(app.buttons["log.strength"].waitForExistence(timeout: 10)
                      || app.buttons["log.cardio"].waitForExistence(timeout: 10),
                      "log picker should open")
    }

    func testQuickActionProgramsNavigates() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.planning"), "Programs chip")
        // Should navigate to the programs/routines planning surface.
        XCTAssertTrue(app.staticTexts["planning.title"].waitForExistence(timeout: 10)
                      || app.descendants(matching: .any)["planning.view"].waitForExistence(timeout: 10),
                      "should navigate to Programs & Routines")
    }

    // MARK: - Header date

    func testHomeHeaderShowsDate() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.descendants(matching: .any)["home.headerDate"].waitForExistence(timeout: 10),
                      "header date should appear beneath the title")
    }

    // MARK: - Coach card science footer

    func testCoachCardScienceFooterBelowStart() {
        let app = XCUIApplication.launched(seeds: ["history"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        // The science toggle sits below the Start button in the footer row.
        let why = app.descendants(matching: .any)["coach.card.why"].firstMatch
        XCTAssertTrue(why.waitForExistence(timeout: 5),
                      "science footer toggle should be present")
        why.tap()
        XCTAssertTrue(app.descendants(matching: .any)["coach.card.citation"].firstMatch.waitForExistence(timeout: 5),
                      "citation should appear after expanding the science footer")
    }
}
