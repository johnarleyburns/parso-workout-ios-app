import XCTest

final class HomeSimplificationUITests: CadenceUITestCase {

    func testCoachCardNoLongerExposesWhyWeekOrTomorrowLinks() {
        let app = XCUIApplication.launched(seeds: ["coachWednesdayComplete"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        XCTAssertFalse(app.buttons["coach.card.whyToday"].exists)
        XCTAssertFalse(app.buttons["coach.card.yourWeek"].exists)
        XCTAssertTrue(app.buttons["coach.card.completeBanner"].exists)
    }

    func testHomeSurfacesYesterdayLastStrengthAndCardio() {
        let app = XCUIApplication.launched(seeds: ["coachYesterdayMixedHistory"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        let lastStrength = app.descendants(matching: .any)["home.fact.lastStrength"].firstMatch
        let lastCardio = app.descendants(matching: .any)["home.fact.lastCardio"].firstMatch
        for _ in 0..<8 where !lastStrength.exists || !lastCardio.exists {
            app.swipeUp()
        }

        XCTAssertTrue(lastStrength.exists, "last strength fact should exist on Home")
        XCTAssertTrue(lastStrength.label.contains("Bench"),
                      "last strength should be yesterday's bench, got: \(lastStrength.label)")
        XCTAssertTrue(lastCardio.exists, "last cardio fact should exist on Home")
        XCTAssertTrue(lastCardio.label.contains("Run"),
                      "last cardio should be yesterday's run, got: \(lastCardio.label)")
    }

    func testCoachCardPreferencesButtonOpensCoachPreferences() {
        let app = XCUIApplication.launched(seeds: ["coachWhyMixedHistory"])
        XCTAssertTrue(app.buttons["coach.card.preferences"].waitForExistence(timeout: 10))
        app.buttons["coach.card.preferences"].tap()

        XCTAssertTrue(app.navigationBars["Coach preferences"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Strength days"].exists || app.staticTexts["Strength days/week"].exists)
    }

    func testCoachCardInsightsButtonOpensDedicatedInsights() {
        let app = XCUIApplication.launched(seeds: ["coachWhyMixedHistory"])
        let insights = app.buttons["coach.card.insights"]
        XCTAssertTrue(insights.waitForExistence(timeout: 10), "Coach card should link to insights")
        insights.tap()

        XCTAssertTrue(app.navigationBars["Coach insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["coach.insights.list"].waitForExistence(timeout: 5))
    }

    func testExportScreenLoads() {
        let app = XCUIApplication.launched(seeds: ["coachCyclePreference"])
        app.buttons["home.settings"].tap()

        let exportLink = app.buttons["settings.export"]
        if !exportLink.exists || !exportLink.isHittable {
            app.swipeUp()
            app.swipeUp()
        }
        if exportLink.waitForExistence(timeout: 5), exportLink.isHittable {
            exportLink.tap()
            if app.navigationBars["Export"].waitForExistence(timeout: 5) {
                XCTAssertTrue(app.textViews["export.preview"].waitForExistence(timeout: 5))
            }
        }
    }
}
