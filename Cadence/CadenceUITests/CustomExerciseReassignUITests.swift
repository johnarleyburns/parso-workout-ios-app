import XCTest

/// P5 (issue 4) — Custom-exercise Reassign should confirm the auto-match first,
/// then only reveal the full rich picker (search + body-part pills) if the user
/// chooses "Pick a different exercise".
final class CustomExerciseReassignUITests: CadenceUITestCase {

    private func openCustomExercises(_ app: XCUIApplication) {
        XCTAssertTrue(app.scrollToHittableAndTap("home.settings"), "open Settings")
        // The Exercises section is below the fold; scroll until the link is hittable.
        let link = app.descendants(matching: .any)["settings.customExercises"]
        var found = link.waitForExistence(timeout: 3) && link.isHittable
        for _ in 0..<8 where !found {
            app.swipeUp()
            found = link.exists && link.isHittable
        }
        XCTAssertTrue(found, "Settings should link to Custom Exercises")
        link.tap()
    }

    func testReassignShowsConfirmationDialogFirst() {
        let app = XCUIApplication.launched(seeds: ["customExerciseNeedsReassign"])
        openCustomExercises(app)

        let reassign = app.buttons["reassign.button"]
        XCTAssertTrue(reassign.waitForExistence(timeout: 10),
                      "An incomplete custom exercise with a match should show Reassign")
        reassign.tap()

        // The confirmation dialog exposes a direct "Reassign to <match>" and a
        // "Pick a different exercise" option — not a bare list.
        XCTAssertTrue(app.buttons["reassign.confirm.yes"].waitForExistence(timeout: 5),
                      "Reassign should first confirm the auto-match")
        XCTAssertTrue(app.buttons["reassign.confirm.pickDifferent"].exists,
                      "Confirmation should offer 'Pick a different exercise'")
    }

    func testPickDifferentRevealsRichPicker() {
        let app = XCUIApplication.launched(seeds: ["customExerciseNeedsReassign"])
        openCustomExercises(app)

        app.buttons["reassign.button"].tap()
        let pickDifferent = app.buttons["reassign.confirm.pickDifferent"]
        XCTAssertTrue(pickDifferent.waitForExistence(timeout: 5))
        pickDifferent.tap()

        // The rich picker has a search field and body-part filter pills.
        XCTAssertTrue(app.descendants(matching: .any)["picker.search"].waitForExistence(timeout: 10)
                      || app.searchFields.firstMatch.waitForExistence(timeout: 5),
                      "Pick a different exercise should reveal the searchable picker")
        // Body-part filter pills live under the Browse tab.
        let browseTab = app.buttons["Browse"]
        if browseTab.waitForExistence(timeout: 5) { browseTab.tap() }
        XCTAssertTrue(app.buttons["picker.filter.all"].waitForExistence(timeout: 5),
                      "Picker should show body-part filter pills in Browse")
    }
}
