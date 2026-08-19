import XCTest

/// The one normal iPhone XCUITest. It covers the minimum end-to-end surface that
/// needs a real simulator: launch, Home expansion, planning, Quick Start, ending,
/// and the post-workout summary. Everything else belongs in headless `swift test`.
final class SmokeLaunchTests: CadenceUITestCase {
    /// The exercise the logging flow adds. A catalog staple, so the picker's
    /// search always resolves it.
    private let exerciseName = "Bench Press"

    @MainActor
    func testIPhoneStrengthWorkoutPlansLogsAndCompletes() {
        // A seeded partner gives the session a real roster, so the flow can log a
        // set for someone other than the owner (field test 2026-08-18 §5b).
        let app = XCUIApplication.launched(seeds: ["person.Sam"])

        XCTAssertEqual(app.state, .runningForeground,
                       "iPhone app terminated or failed to reach the foreground during cold launch")
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 25),
                      "Home did not load")
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10),
                      "Coach card did not render on Home")
        XCTAssertTrue(app.buttons["home.logWorkout"].waitForExistence(timeout: 5),
                      "Home did not show the previous-workout log action")
        // Field test 2026-08-18 #9/#11: the Suggested Workout blurb is gone and the
        // CTA is a full-width sibling below the card, not a child of it.
        XCTAssertFalse(app.staticTexts["Suggested Workout"].exists,
                       "Coach card still shows the removed Suggested Workout blurb")
        if app.descendants(matching: .any)["home.coachRecommendation"].exists {
            let cta = app.buttons["home.coachRecommendation.start"]
            XCTAssertTrue(cta.waitForExistence(timeout: 5),
                          "Do Coach's Workout is missing below the coach card")
            XCTAssertEqual(cta.frame.height, app.buttons["home.startWorkout"].frame.height,
                           accuracy: 1,
                           "Do Coach's Workout does not match Home Start Workout's height")
            XCTAssertGreaterThan(cta.frame.minY,
                                 app.descendants(matching: .any)["home.coachSuggestions.card"].frame.minY,
                                 "Do Coach's Workout is not below the Coach's Suggestions card")
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

        // Field test 2026-08-18 #7: the This Week gear deep-links to Coach & Plan
        // and backs out to Home, not to Settings.
        XCTAssertTrue(app.scrollToHittableAndTap("home.week.coachSettings"),
                      "This Week did not offer a Coach & Plan shortcut")
        XCTAssertTrue(app.navigationBars["Coach & Plan"].waitForExistence(timeout: 10),
                      "This Week gear did not open Coach & Plan")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 10),
                      "Back from Coach & Plan did not return to Home")
        XCTAssertFalse(app.navigationBars["Settings"].exists,
                       "Back from Coach & Plan landed on Settings instead of Home")
        if app.buttons["home.suggestions.showMore"].exists {
            XCTAssertTrue(app.scrollToHittableAndTap("home.suggestions.showMore"),
                          "Coach's Suggestions did not show only the first warning before Show more...")
            XCTAssertTrue(app.scrollToHittableAndTap("home.suggestions.showLess"),
                          "Coach's Suggestions did not put Show less at the bottom")
        }
        XCTAssertFalse(app.descendants(matching: .any)["home.workoutHistory"].exists,
                       "Home still contains the duplicate Workout History card")

        // Field test 2026-08-18 #6: Workouts Today rows carry a plan-source badge.
        XCTAssertTrue(app.descendants(matching: .any)["home.workoutsToday"].waitForExistence(timeout: 10),
                      "Workouts Today card is missing")
        XCTAssertFalse(app.staticTexts["PLANNED"].exists,
                       "Workouts Today still uses the bare PLANNED badge")

        // Field test 2026-08-18 #10: at most one science row per coach output.
        // The bug rendered one row per *citation*, typically 6+.
        let science = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'The science'"))
        XCTAssertLessThanOrEqual(science.count, 3,
                                 "Coach surfaces render a separate science row per citation again")

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

        // Field test 2026-08-18 #4: a partner is addable from the plan itself —
        // no Edit mode — and the coach immediately fills THEIR plan for the
        // owner's exercise. Unguarded: every step below fails if it is missing.
        XCTAssertTrue(app.buttons["editor.addExercise"].waitTap(timeout: 5),
                      "Plan editor did not offer Add Exercise")
        XCTAssertTrue(app.pickExerciseFromPresentedPicker(exerciseName),
                      "Could not add \(exerciseName) to the plan")
        XCTAssertTrue(app.buttons["editor.edit"].waitTap(timeout: 5),
                      "Plan editor did not offer Done")
        XCTAssertTrue(app.scrollToHittableAndTap("editor.showPartnerPicker"),
                      "Workout Plan does not expose the partner picker outside Edit mode")
        XCTAssertTrue(app.scrollToHittableAndTap("editor.partner.Sam"),
                      "Could not add a partner from the read-only Workout Plan")
        XCTAssertTrue(app.descendants(matching: .any)["editor.partnerChip.Sam"]
                        .waitForExistence(timeout: 5),
                      "The added partner is not shown on the Training partners card")
        XCTAssertTrue(app.descendants(matching: .any)["editor.exercisePerformer.\(exerciseName).Sam"]
                        .waitForExistence(timeout: 5),
                      "The coach did not fill the partner's plan for the owner's exercise")
        XCTAssertTrue(app.descendants(matching: .any)["editor.exercisePerformer.\(exerciseName).Me"].exists,
                      "The owner's own line disappeared once a partner was added")

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

        // Field test 2026-08-18 §5b: the flow logs real sets with a partner, the
        // way the watch smoke test does. Without this every summary assertion
        // below is vacuous — the session would contain no exercises at all.
        XCTAssertTrue(app.addSessionPartner("Sam"), "Could not add a training partner to the session")
        XCTAssertTrue(app.pickExercise(exerciseName),
                      "Could not add \(exerciseName) to the live session")
        XCTAssertTrue(app.saveSetInEditor(), "Owner's set did not save")
        app.dismissRestBar()
        XCTAssertTrue(app.logPartnerSet(exercise: exerciseName, partner: "Sam"),
                      "Partner's set did not save")
        app.dismissRestBar()

        XCTAssertTrue(app.scrollToHittableAndTap("workout.end"), "End workout button did not tap")
        let end = app.dialogButton("workout.endConfirm")
        XCTAssertTrue(end.waitForExistence(timeout: 5), "End confirmation did not appear")
        end.tap()

        XCTAssertTrue(app.descendants(matching: .any)["summary.title"].waitForExistence(timeout: 15),
                      "post-workout summary did not render")

        // Field test 2026-08-18 #1: the summary expands an exercise read-only, one
        // row per performer. Unguarded — the flow above logged the sets, so an
        // absent row is a real failure rather than an empty workout.
        let exerciseRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'summary.exercise'")).firstMatch
        XCTAssertTrue(exerciseRow.waitForExistence(timeout: 10),
                      "Summary has no exercise row for the logged sets")
        exerciseRow.tap()
        XCTAssertFalse(app.buttons["session.addExercise"].exists,
                       "Expanding a summary exercise navigated into the editor")
        XCTAssertTrue(app.descendants(matching: .any)["summary.title"].exists,
                      "Expanding a summary exercise left the summary")
        XCTAssertTrue(app.descendants(matching: .any)
                        .matching(NSPredicate(format: "identifier ENDSWITH '.performer.Me'"))
                        .firstMatch.waitForExistence(timeout: 5),
                      "Expanded summary exercise is missing the owner's per-performer row")
        XCTAssertTrue(app.descendants(matching: .any)
                        .matching(NSPredicate(format: "identifier ENDSWITH '.performer.Sam'"))
                        .firstMatch.exists,
                      "Expanded summary exercise is missing the partner's per-performer row")

        XCTAssertTrue(app.buttons["summary.done"].waitTap(timeout: 10), "summary Done did not tap")
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 10),
                      "Home did not return after summary")

        // Field test 2026-08-18 #6: the finished workout is a tappable Workouts
        // Today row.
        let todayRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'home.today.row.'")).firstMatch
        XCTAssertTrue(todayRow.waitForExistence(timeout: 10),
                      "Completed workout did not appear in Workouts Today")
    }
}
