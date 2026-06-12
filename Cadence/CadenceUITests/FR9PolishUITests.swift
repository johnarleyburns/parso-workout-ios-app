import XCTest

/// Field-testing Round 4 Part B — P1 polish. Covers the user-visible polish:
/// the merged "Recent workouts" list (cardio counts as a workout, #10) and the
/// auto-save-to-Health setting (#8). The three screen-flash fixes (#1/#5/#9) are
/// animation-only and are covered indirectly by the FR7/FR8 flows still landing
/// on the right screens.
final class FR9PolishUITests: CadenceUITestCase {

    // #10 — Home surfaces strength sessions and cardio recordings in one section.
    func testHomeRecentWorkoutsMergesCardioAndStrength() {
        let app = XCUIApplication.launched(seeds: ["historyMixed"])
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 25), "home")

        // The recent list sits below the fold on the scrolling dashboard.
        let session = app.buttons["home.sessionRow"].firstMatch
        let cardio = app.buttons["home.cardioRow.walk"].firstMatch
        var merged = false
        for _ in 0..<8 {
            if session.exists && cardio.exists { merged = true; break }
            app.swipeUp()
        }
        XCTAssertTrue(merged, "strength + cardio should share one Recent workouts list")
    }

    // #8 — the auto-save-to-Apple-Health preference is exposed in Settings.
    func testAutoSaveHealthSettingExists() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.settings"), "open Settings")

        let toggle = app.switches["settings.autoSaveHealth"]
        var found = false
        for _ in 0..<8 {
            if toggle.exists { found = true; break }
            app.swipeUp()
        }
        XCTAssertTrue(found, "Settings should expose the auto-save-to-Health toggle")
    }
}
