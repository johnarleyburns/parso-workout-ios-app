import XCTest

/// Home "What you did" card fixes (Home/Your Plan bug-fix batch, phase B):
/// - Fix 3: tapping the strength "What you did" row opens that workout's session
///   detail (decision #3 — the whole card opens the workout, not per-exercise).
/// - Fix 2: opening a past workout from history and adding a set must NOT start the
///   rest timer (it only fires for the live active session).
final class HomeWhatYouDidNavUITests: CadenceUITestCase {

    /// Tapping the last-strength "What you did" row navigates to that session.
    func testTapLastStrengthOpensSessionDetail() {
        let app = XCUIApplication.launched(seeds: ["coachYesterdayMixedHistory"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        let lastStrength = app.descendants(matching: .any)["home.fact.lastStrength"].firstMatch
        for _ in 0..<8 where !lastStrength.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(lastStrength.exists, "last strength fact should exist on Home")
        lastStrength.tap()

        // The pushed session detail shows the "Push Day" title and the add-exercise
        // control from the editable SessionView.
        let addExercise = app.buttons["session.addExercise"]
        let title = app.navigationBars["Push Day"]
        XCTAssertTrue(addExercise.waitForExistence(timeout: 10) || title.waitForExistence(timeout: 10),
                      "tapping the last-strength card should open the session detail")
    }

    /// Editing a past workout (opened from Home's "What you did") and adding a set
    /// must not start the rest timer — there is nothing to rest from.
    func testEditingPastWorkoutDoesNotStartRestTimer() {
        let app = XCUIApplication.launched(seeds: ["coachYesterdayMixedHistory"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        let lastStrength = app.descendants(matching: .any)["home.fact.lastStrength"].firstMatch
        for _ in 0..<8 where !lastStrength.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(lastStrength.exists, "last strength fact should exist on Home")
        lastStrength.tap()

        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 15),
                      "should land on the editable session")

        // Add a set to the existing Bench Press exercise.
        let addSet = app.buttons["set.add.Bench Press"]
        for _ in 0..<6 where !addSet.isHittable { app.swipeUp() }
        if addSet.waitForExistence(timeout: 5) {
            addSet.tap()
            // Log the set via the inline editor's save control.
            if app.buttons["inline.save"].waitForExistence(timeout: 10) {
                app.buttons["inline.save"].tap()
            }
        }

        // The rest-timer bar must never appear when editing a past workout.
        XCTAssertFalse(app.buttons["rest.skip"].waitForExistence(timeout: 3),
                       "rest timer must not start when editing a past (non-live) workout")
    }
}
