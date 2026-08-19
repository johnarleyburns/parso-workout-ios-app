import XCTest

/// The one normal iPhone XCUITest. It covers the minimum end-to-end surface that
/// needs a real simulator: launch, Home expansion, planning, Quick Start, ending,
/// and the post-workout summary. Everything else belongs in headless `swift test`.
final class SmokeLaunchTests: CadenceUITestCase {
    @MainActor
    func testIPhoneStrengthWorkoutPlansLogsAndCompletes() {
        let app = XCUIApplication.launched()

        XCTAssertEqual(app.state, .runningForeground,
                       "iPhone app terminated or failed to reach the foreground during cold launch")
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 25),
                      "Home did not load")
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10),
                      "Coach card did not render on Home")
        XCTAssertTrue(app.buttons["home.logWorkout"].waitForExistence(timeout: 5),
                      "Home did not show the previous-workout log action")
        if app.descendants(matching: .any)["home.coachRecommendation"].exists {
            XCTAssertTrue(app.buttons["home.coachRecommendation.start"].waitForExistence(timeout: 5),
                          "Home did not show Do Coach's Workout at the top of the coach card")
            XCTAssertFalse(app.buttons["home.coachRecommendation.preview"].exists,
                           "Coach card still exposes the removed Preview Workout action")
        }

        XCTAssertTrue(app.scrollToHittableAndTap("home.week.showMore"),
                      "This Week did not offer Show more")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.volumeHeading"].waitForExistence(timeout: 5),
                      "This Week did not expand in place")
        XCTAssertTrue(app.scrollToHittableAndTap("home.volume.legs"),
                      "Expanded This Week did not expose the Legs volume row")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.volumeHeading"].exists,
                      "Expanded This Week did not label the body-part rows as Volume")
        XCTAssertTrue(app.scrollToHittableAndTap("home.week.showLess"),
                      "Expanded This Week did not show Show less")
        if app.buttons["home.suggestions.showMore"].exists {
            XCTAssertTrue(app.scrollToHittableAndTap("home.suggestions.showMore"),
                          "Coach's Suggestions did not show only the first warning before Show more...")
            XCTAssertTrue(app.scrollToHittableAndTap("home.suggestions.showLess"),
                          "Coach's Suggestions did not put Show less at the bottom")
        }
        XCTAssertFalse(app.descendants(matching: .any)["home.workoutHistory"].exists,
                       "Home still contains the duplicate Workout History card")

        XCTAssertTrue(app.scrollToHittableAndTap("home.startWorkout"),
                      "Home Start Workout did not open")
        XCTAssertTrue(app.buttons["selectWorkout.custom"].label.contains("Custom Workout"),
                      "Start Workout custom action still uses the old label")

        // Field test 2026-08-18 #3: the full-width strength actions are one height.
        let quick = app.buttons["selectWorkout.quickStart"]
        let custom = app.buttons["selectWorkout.custom"]
        let coach = app.buttons["selectWorkout.coach"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5), "Start Workout lost Quick Start")
        let quickHeight = quick.frame.height
        XCTAssertEqual(quickHeight, custom.frame.height, accuracy: 1,
                       "Quick Start and Custom Workout are different heights")
        if coach.exists {
            XCTAssertEqual(quickHeight, coach.frame.height, accuracy: 1,
                           "Coach's Workout is a different height from Quick Start")
        }

        XCTAssertTrue(app.scrollToHittableAndTap("selectWorkout.custom"),
                      "Start Workout did not offer Custom Workout beneath Quick Start")
        XCTAssertTrue(app.buttons["editor.start"].waitForExistence(timeout: 10),
                      "Custom workout did not open the Workout Plan editor")
        XCTAssertTrue(app.buttons["editor.start"].label.contains("Start Workout"),
                      "Workout Plan start action is not labeled Start Workout")
        XCTAssertEqual(app.buttons["editor.start"].frame.height, quickHeight, accuracy: 1,
                       "Workout Plan Start Workout is a different height from Start Workout's actions")
        XCTAssertTrue(app.buttons["editor.addExercise"].waitForExistence(timeout: 5),
                      "Custom Workout did not open in edit mode")
        // Field test 2026-08-18 #5: the plan editor is a Home-rhythm scroll surface.
        XCTAssertTrue(app.descendants(matching: .any)["editor.partners"].waitForExistence(timeout: 5),
                      "Workout Plan lost its Training partners card")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["selectWorkout.cancel"].waitForExistence(timeout: 5),
                      "Could not return to Start Workout")
        app.buttons["selectWorkout.cancel"].tap()

        XCTAssertTrue(app.scrollToHittableAndTap("tab.plan"), "Plan tab did not open")
        XCTAssertTrue(app.descendants(matching: .any)["planning"].waitForExistence(timeout: 10),
                      "Programs screen did not render")
        app.popToHome()

        XCTAssertTrue(app.startEmptyStrengthWorkout(), "Quick Start did not enter the workout")
        XCTAssertFalse(app.buttons["editor.showSettings"].exists,
                       "Quick Start unexpectedly opened workout settings")

        XCTAssertTrue(app.scrollToHittableAndTap("workout.end"), "End workout button did not tap")
        let end = app.dialogButton("workout.endConfirm")
        XCTAssertTrue(end.waitForExistence(timeout: 5), "End confirmation did not appear")
        end.tap()

        XCTAssertTrue(app.descendants(matching: .any)["summary.title"].waitForExistence(timeout: 15),
                      "post-workout summary did not render")

        // Field test 2026-08-18 #1: the summary expands an exercise read-only.
        let exerciseRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'summary.exercise'")).firstMatch
        if exerciseRow.exists {
            exerciseRow.tap()
            XCTAssertFalse(app.buttons["session.addExercise"].exists,
                           "Expanding a summary exercise navigated into the editor")
            XCTAssertTrue(app.descendants(matching: .any)["summary.title"].exists,
                          "Expanding a summary exercise left the summary")
        }
        XCTAssertTrue(app.buttons["summary.done"].waitTap(timeout: 10), "summary Done did not tap")
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 10),
                      "Home did not return after summary")
    }
}
