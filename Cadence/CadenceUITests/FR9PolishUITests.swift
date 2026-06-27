import XCTest

/// Field-testing Round 4 Part B — P1 polish. Covers the user-visible polish:
/// unified History (cardio counts as a workout, #10) and the auto-save-to-Health
/// setting (#8). The three screen-flash fixes (#1/#5/#9) are animation-only and
/// are covered indirectly by the FR7/FR8 flows still landing on the right screens.
final class FR9PolishUITests: CadenceUITestCase {

    // #10 — History surfaces strength sessions and cardio recordings in one list.
    func testHistoryMergesCardioAndStrength() {
        let app = XCUIApplication.launched(seeds: ["historyMixed"])
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 25), "home")

        XCTAssertTrue(app.scrollToHittableAndTap("home.train"), "open History from Home")
        XCTAssertTrue(app.buttons["session.row"].firstMatch.waitForExistence(timeout: 25),
                      "strength sessions should list")
        XCTAssertTrue(app.buttons["history.cardioRow.walk"].firstMatch.waitForExistence(timeout: 25),
                      "the seeded walk should appear in the same list as strength")
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
