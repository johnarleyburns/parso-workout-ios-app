import XCTest
import UIKit

/// The one normal iPhone XCUITest. It covers the minimum end-to-end surface that
/// needs a real simulator: launch, Home start routing, scheduled-workout entry, ending,
/// and the post-workout summary. Everything else belongs in headless `swift test`.
final class SmokeLaunchTests: CadenceUITestCase {
    /// The exercise the logging flow adds. A catalog staple, so the picker's
    /// search always resolves it.
    private let exerciseName = "Bench Press"

    @MainActor
    func testIPhoneStrengthWorkoutPlansLogsAndCompletes() {
        // A seeded partner gives the session a real roster, so the flow can log a
        // set for someone other than the owner (field test 2026-08-18 §5b). The
        // watch-stop seam makes the cardio end below provable, not vacuous.
        let persistenceTestID = UUID().uuidString
        let app = XCUIApplication.launched(seeds: ["person.Sam"],
                                           extraArgs: ["-uiTestWatchStop",
                                                       "-uiTestPersistentStore",
                                                       "-uiTestStoreID", persistenceTestID])

        XCTAssertEqual(app.state, .runningForeground,
                       "iPhone app terminated or failed to reach the foreground during cold launch")
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 25),
                      "Home did not load")
        XCTAssertTrue(app.buttons["selectWorkout.startWorkout"].exists,
                      "Today did not show its single Start Workout entry")
        XCTAssertFalse(app.buttons["selectWorkout.quickStart"].exists,
                       "Today still exposes Quick Start")
        XCTAssertFalse(app.buttons["selectWorkout.moreWays"].exists,
                       "Today still exposes More ways to start")
        XCTAssertFalse(app.buttons["selectWorkout.suggestWorkout"].exists,
                       "Today still exposes the retired Workout for You entry")
        XCTAssertTrue(app.buttons["tab.today"].exists,
                      "Today is not exposed as the primary activity tab")
        XCTAssertTrue(app.buttons["tab.thisWeek"].exists,
                      "This Week is not exposed as a primary review tab")
        XCTAssertTrue(app.buttons["tab.progress"].exists,
                      "Progress is not exposed as a primary tab")
        XCTAssertTrue(app.buttons["tab.settings"].exists,
                      "Settings is not exposed as a primary tab")
        XCTAssertFalse(app.buttons["tab.home"].exists,
                       "The retired Home tab label is still exposed")
        XCTAssertFalse(app.buttons["tab.tests"].exists,
                       "Tests is still exposed as a primary tab")
        XCTAssertFalse(app.buttons["tab.plan"].exists,
                       "Retired Plan is still exposed as a primary tab")

        // The iPad delivery check intentionally covers only regular-width
        // Home/settings surfaces. The full end-to-end flow below remains
        // the single iPhone smoke path.
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertFalse(app.buttons["tab.plan"].exists,
                           "Retired Plan tab is still exposed on iPad")
            XCTAssertTrue(app.buttons["tab.settings"].waitTap(timeout: 10),
                          "iPad Home did not expose Settings tab")
            // Settings is a lazy Form on iPad; use the helper that swipes before
            // resolving the row so the identifier can materialize off-screen.
            XCTAssertTrue(app.scrollToAndTapButton("settings.transparency", maxSwipes: 20),
                          "iPad Settings did not expose Transparency & Control")
            XCTAssertTrue(app.navigationBars["Transparency & Control"].waitForExistence(timeout: 10),
                          "iPad Transparency & Control did not open")
            return
        }

        XCTAssertTrue(app.buttons["tab.settings"].waitTap(timeout: 10),
                      "Settings tab did not open")
        for identifier in ["settings.savedWorkouts", "settings.customExercises",
                           "settings.excludedExercises", "settings.coach.insights",
                           "settings.coach.about", "settings.coach.methodology", "settings.coachUpdates",
                           "settings.about", "settings.support"] {
            XCTAssertTrue(app.scrollToAndTapButton(identifier, maxSwipes: 20),
                          "Settings did not expose \(identifier)")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.buttons["tab.today"].waitTap(timeout: 10),
                      "Returning to Today did not land on Today")
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Returning from More did not land on Home")

        // Progress is summary-first and keeps Tests behind its own disclosure;
        // this is the smoke contract for the retired More → Tests route.
        XCTAssertTrue(app.buttons["tab.progress"].waitTap(timeout: 10),
                      "Progress tab did not open")
        XCTAssertTrue(app.descendants(matching: .any)["progress"].waitForExistence(timeout: 10),
                      "Progress surface did not render")
        XCTAssertTrue(app.descendants(matching: .any)["progress.focus.consistency"].exists,
                      "Progress did not default to its selected Consistency question")
        XCTAssertFalse(app.descendants(matching: .any)["progress.focus.muscleVolume"].exists,
                       "Progress displayed more than one question summary at once")
        XCTAssertTrue(app.buttons["progress.fullHistory"].exists,
                      "Progress did not expose full History")
        XCTAssertTrue(app.scrollToHittableAndTap("progress.testsDisclosure"),
                      "Progress did not expose its Tests disclosure")
        XCTAssertTrue(app.buttons["progress.performTest"].waitForExistence(timeout: 5),
                      "Progress Tests disclosure did not expose Perform a Test…")
        XCTAssertTrue(app.scrollToHittableAndTap("progress.testsDisclosure"),
                      "Progress Tests disclosure did not collapse")
        XCTAssertTrue(app.scrollToHittableAndTap("progress.trendsDisclosure"),
                      "Progress did not expose Trends")
        XCTAssertEqual(app.buttons["progress.trendsDisclosure"].value as? String, "Expanded")
        XCTAssertEqual(app.buttons["progress.testsDisclosure"].value as? String, "Collapsed",
                       "Opening Trends left the Tests detail expanded too")
        XCTAssertTrue(app.scrollToHittableAndTap("progress.strengthDisclosure"),
                      "Progress did not expose Strength over time")
        XCTAssertEqual(app.buttons["progress.strengthDisclosure"].value as? String, "Expanded")
        XCTAssertEqual(app.buttons["progress.trendsDisclosure"].value as? String, "Collapsed",
                       "Opening Strength left Trends expanded too")
        XCTAssertTrue(app.buttons["tab.today"].waitTap(timeout: 10),
                      "Returning from Progress did not land on Today")
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Today did not reload after Progress")

        // HIIT info must expose the exact expanded runner sequence. This stays
        // inside the single iPhone smoke flow required by the test-pyramid
        // guardrail, while proving the new outline is not merely a compact
        // rounds/work/rest summary.
        openStartWorkout(app)
        expandAllCardioIfNeeded(app)
        let gpsTileLabels = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'GPS'"))
        XCTAssertEqual(gpsTileLabels.count, 0,
                       "The compact cardio picker must leave GPS to pre-workout settings")
        for identifier in ["cardioPicker.start.run", "cardioPicker.start.walk", "cardioPicker.start.cycle",
                           "cardioPicker.start.rowing", "cardioPicker.start.swim", "cardioPicker.start.hiit",
                           "cardioPicker.start.boxing", "cardioPicker.start.other"] {
            XCTAssertTrue(app.scrollToElement(identifier),
                          "Start Workout did not offer \(identifier)")
        }
        XCTAssertFalse(app.buttons["cardioPicker.schedule"].exists,
                       "Normal Cardio Picker exposes a schedule action; scheduling must be a separate intent")
        XCTAssertTrue(app.scrollToHittableAndTap("cardioPicker.start.hiit"),
                      "Start Workout did not offer HIIT")
        XCTAssertTrue(app.navigationBars["HIIT"].waitForExistence(timeout: 10),
                      "HIIT setup did not open")
        XCTAssertTrue(app.buttons["About Tabata"].waitTap(timeout: 10),
                      "HIIT setup did not expose Tabata info")
        XCTAssertTrue(app.navigationBars["Tabata"].waitForExistence(timeout: 10),
                      "Tabata info sheet did not open")
        let intervalOutline = app.descendants(matching: .any)["interval.info.outline"]
        XCTAssertTrue(intervalOutline.waitForExistence(timeout: 5),
                      "Tabata info did not show the expanded outline")
        let intervalPhases = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'interval.info.outline.phase.'"))
        XCTAssertEqual(intervalPhases.count, 18,
                       "Tabata outline must show warm-up, 8 work/rest pairs, and cool-down")
        XCTAssertTrue(intervalPhases.element(boundBy: 0).label.contains("Warm Up"))
        XCTAssertTrue(intervalPhases.element(boundBy: 0).label.contains("5:00"))
        XCTAssertTrue(intervalPhases.element(boundBy: 1).label.contains("20 sec"))
        XCTAssertTrue(intervalPhases.element(boundBy: 2).label.contains("10 sec"))
        XCTAssertTrue(intervalPhases.element(boundBy: 17).label.contains("Cool Down"))
        XCTAssertTrue(intervalPhases.element(boundBy: 17).label.contains("5:00"))
        XCTAssertTrue(app.buttons["Done"].waitTap(timeout: 5),
                      "Tabata info sheet did not close")
        XCTAssertTrue(app.buttons["interval.cancel"].waitTap(timeout: 5),
                      "HIIT setup did not close")
        // Start Workout is now inline on Today; closing the nested HIIT setup
        // returns directly to the same surface, with no picker sheet to cancel.

        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10),
                      "Coach card did not render on Home")
        openStartWorkout(app)
        XCTAssertTrue(app.scrollToHittableAndTap("startWorkout.pick.strength"),
                      "Start Workout did not expose Pick Your Own Strength")
        XCTAssertTrue(app.navigationBars["Pick Workout"].waitForExistence(timeout: 5),
                      "Pick Your Own Strength did not open Pick Workout")
        XCTAssertTrue(app.scrollToHittableAndTap("pickWorkout.schedule"),
                      "Pick Workout did not expose Schedule Workout")
        XCTAssertTrue(app.navigationBars["Workout Plan"].waitForExistence(timeout: 10),
                      "Schedule Workout did not open the Workout Plan")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Returning from More actions Schedule Workout did not land on Home")
        openStartWorkout(app)
        XCTAssertTrue(app.scrollToHittableAndTap("startWorkout.pick.strength"),
                      "Start Workout did not expose Pick Your Own Strength")
        XCTAssertTrue(app.navigationBars["Pick Workout"].waitForExistence(timeout: 5),
                      "Pick Your Own Strength did not open Pick Workout")
        XCTAssertTrue(app.scrollToHittableAndTap("pickWorkout.log"),
                      "Pick Workout did not expose Log Workout")
        XCTAssertTrue(app.navigationBars["Log Workout"].waitForExistence(timeout: 5),
                      "Log Previous Workout did not open the existing log flow")
        XCTAssertTrue(app.buttons["logType.cancel"].waitTap(timeout: 5),
                      "Log Previous Workout did not offer Cancel")
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 5),
                      "Cancelling Log Previous Workout did not return Home")
        // Field test 2026-08-18 #9/#11: the Suggested Workout blurb is gone and the
        // CTA is a full-width sibling below the card, not a child of it.
        XCTAssertFalse(app.staticTexts["Suggested Workout"].exists,
                       "Coach card still shows the removed Suggested Workout blurb")
        XCTAssertTrue(app.scrollToHittableAndTap("home.observations.show"),
                      "Home did not expose Observations")
        XCTAssertTrue(app.staticTexts["Observations"].waitForExistence(timeout: 5),
                      "Observations did not expand")
        XCTAssertFalse(app.staticTexts["Coach’s Suggestions"].exists)
        XCTAssertFalse(app.staticTexts["Coach's Suggestions"].exists)
        XCTAssertFalse(app.staticTexts["Coach's Workout"].exists)
        XCTAssertFalse(app.staticTexts["Do Coach's Workout"].exists)
        XCTAssertFalse(app.buttons["home.suggestWorkout"].exists,
                       "Home still exposes the removed Suggest a Workout CTA")
        XCTAssertFalse(app.buttons["home.coachRecommendation.preview"].exists,
                       "Coach card still exposes the removed Preview Workout action")

        XCTAssertTrue(app.scrollToHittableAndTap("home.readiness.show"),
                      "Home did not expose Readiness")
        XCTAssertTrue(app.descendants(matching: .any)["home.readiness"]
                        .waitForExistence(timeout: 5),
                      "Readiness disclosure did not reveal its check-in card")

        XCTAssertTrue(app.buttons["tab.thisWeek"].waitTap(timeout: 10),
                      "This Week tab did not open")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.sets.muscleMap"].waitForExistence(timeout: 5),
                      "This Week did not show the compact muscle map")
        XCTAssertTrue(app.buttons["home.week.sets.muscleMap.front"].exists,
                      "This Week did not expose the Front segment")
        XCTAssertTrue(app.buttons["home.week.sets.muscleMap.back"].exists,
                      "This Week did not expose the Back segment")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.muscle.front.shoulders"].exists,
                      "This Week did not expose a front callout by default")
        XCTAssertFalse(app.descendants(matching: .any)["home.week.muscle.back.lats"].exists,
                       "This Week rendered the hidden back map alongside the selected front map")
        XCTAssertTrue(app.scrollToHittableAndTap("home.week.muscle.front.chest"),
                      "Front anatomy region was not tappable")
        XCTAssertTrue(app.navigationBars["Weekly muscle detail"].waitForExistence(timeout: 5),
                      "Front muscle tap did not open weekly detail")
        XCTAssertTrue(app.buttons["Done"].waitTap(timeout: 5),
                      "Weekly muscle detail could not be dismissed")
        XCTAssertTrue(app.scrollToHittableAndTap("home.week.sets.muscleMap.back"),
                      "This Week could not switch to the Back segment")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.muscle.back.lats"].waitForExistence(timeout: 5),
                      "This Week did not replace the front map with the selected back map")
        XCTAssertFalse(app.descendants(matching: .any)["home.week.muscle.front.chest"].exists,
                       "This Week kept the front callouts visible after switching to Back")
        XCTAssertTrue(app.scrollToHittableAndTap("home.week.muscle.back.lats"),
                      "Back anatomy region was not tappable")
        XCTAssertTrue(app.navigationBars["Weekly muscle detail"].waitForExistence(timeout: 5),
                      "Back muscle tap did not open weekly detail")
        XCTAssertTrue(app.buttons["Done"].waitTap(timeout: 5),
                      "Back muscle detail could not be dismissed")
        XCTAssertTrue(app.scrollToHittableAndTap("home.week.sets.showMore"),
                      "This Week did not expose the independent Sets per Muscle Group disclosure")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.sets.heading"].waitForExistence(timeout: 5),
                      "Sets per Muscle Group did not expand in place")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.sets.row.quadriceps"].exists,
                      "Expanded This Week did not expose the Quads sets row")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.sets.row.chest"].exists,
                      "Sets per Muscle Group does not list Chest")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.sets.row.lats"].exists,
                      "Sets per Muscle Group does not list Lats")
        XCTAssertFalse(app.descendants(matching: .any)["home.week.group.strength"].exists,
                       "Opening Sets also exposed strength history")
        XCTAssertFalse(app.descendants(matching: .any)["home.week.group.cardio"].exists,
                       "Opening Sets also exposed cardio history")
        // The Sets list is the sole muscle-volume breakdown; the old duplicate
        // Volume/Muscles identifiers and This Week history card are retired.
        XCTAssertFalse(app.descendants(matching: .any)["home.week.muscles"].exists,
                       "The redundant Muscles breakdown is still on Home")
        XCTAssertFalse(app.descendants(matching: .any)["home.muscle.chest"].exists,
                       "The old per-muscle row identifiers are still present")
        XCTAssertFalse(app.staticTexts["Volume"].exists,
                       "This Week still exposes the retired duplicate Volume heading")
        XCTAssertFalse(app.descendants(matching: .any)["home.myHistory"].exists,
                       "This Week still exposes the retired My History section")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.sets.science"].exists,
                      "Weekly volume does not expose its multi-reference science link")
        XCTAssertTrue(app.scrollToHittableAndTap("home.week.sets.showLess"),
                      "Sets per Muscle Group disclosure did not collapse")
        XCTAssertTrue(app.scrollToHittableAndTap("home.week.cardio.showMore"),
                      "This Week did not expose the Cardio disclosure")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.cardioMinutes"].exists,
                      "Expanded Cardio does not explain the moderate-equivalent cardio total")
        XCTAssertFalse(app.descendants(matching: .any)["home.week.sets.heading"].exists,
                       "Opening Cardio left Sets expanded at the same time")
        let cardioMinutes = app.descendants(matching: .any)["home.week.cardioMinutes"]
        let leakedSourceTokens = cardioMinutes.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'dashboard.cardioDetail' OR label CONTAINS[c] 'Int('"))
        XCTAssertEqual(leakedSourceTokens.count, 0,
                       "Cardio Minutes must render values, never source-code interpolation")
        XCTAssertTrue(app.scrollToHittableAndTap("home.week.sets.showMore"),
                      "This Week could not switch its focused detail back to Sets")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.sets.heading"].waitForExistence(timeout: 5),
                      "Switching to Sets did not reveal its details")
        XCTAssertFalse(app.descendants(matching: .any)["home.week.cardioMinutes"].exists,
                       "Switching to Sets left Cardio expanded at the same time")
        XCTAssertTrue(app.scrollToHittableAndTap("home.week.sets.showLess"),
                      "Sets disclosure did not collapse after the exclusive-mode check")
        XCTAssertTrue(app.buttons["tab.today"].waitTap(timeout: 10),
                      "Could not return to Today after reviewing This Week")
        if app.buttons["home.observations.showMore"].exists {
            XCTAssertTrue(app.scrollToHittableAndTap("home.observations.showMore"),
                          "Observations did not show only the first warning before Show more...")
            XCTAssertTrue(app.scrollToHittableAndTap("home.observations.showLess"),
                          "Observations did not put Show less at the bottom")
        }
        XCTAssertFalse(app.descendants(matching: .any)["home.workoutHistory"].exists,
                       "Home still contains the duplicate Workout History card")

        // Field test 2026-08-18 #6: Workouts Today rows carry a plan-source badge.
        XCTAssertTrue(app.descendants(matching: .any)["home.myWorkouts"].waitForExistence(timeout: 10),
                      "My Workouts card is missing")
        XCTAssertFalse(app.staticTexts["PLANNED"].exists,
                       "Workouts Today still uses the bare PLANNED badge")

        // Field test 2026-08-18 #10: at most one science row per coach output.
        // The bug rendered one row per *citation*, typically 6+.
        let science = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'The science'"))
        XCTAssertLessThanOrEqual(science.count, 3,
                                 "Coach surfaces render a separate science row per citation again")

        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Home inline Start Workout did not render")
        openStartWorkout(app)
        XCTAssertTrue(app.staticTexts["Workouts Created for You"].exists,
                      "Start Workout lost its created-for-you section")
        XCTAssertTrue(app.staticTexts["Pick Your Own Workout"].exists,
                      "Start Workout lost its pick-your-own section")
        XCTAssertTrue(app.buttons["startWorkout.created.strength"].exists,
                      "Start Workout lost created Strength")
        XCTAssertTrue(app.buttons["startWorkout.created.cardio"].exists,
                      "Start Workout lost created Cardio")
        XCTAssertTrue(app.buttons["startWorkout.pick.strength"].exists,
                      "Start Workout lost pick Strength")
        XCTAssertTrue(app.buttons["startWorkout.pick.cardio"].exists,
                      "Start Workout lost pick Cardio")

        // The created-for-you Cardio branch remains a reviewable suggestion.
        XCTAssertTrue(app.scrollToHittableAndTap("startWorkout.created.cardio"),
                      "Start Workout Cardio recommendation was not tappable")
        XCTAssertTrue(app.descendants(matching: .any)["suggestedCardio.preview"]
                        .waitForExistence(timeout: 45),
                      "Start Workout Cardio did not produce a reviewable suggestion")
        XCTAssertTrue(app.buttons["suggestedCardio.start"].exists,
                      "Cardio suggestion did not expose Start")
        XCTAssertTrue(app.buttons["suggestedCardio.cancel"].waitTap(timeout: 5),
                      "Cardio suggestion could not be cancelled")
        XCTAssertTrue(app.buttons["selectWorkout.startWorkout"].waitForExistence(timeout: 5),
                      "Cancelling Cardio suggestion did not return to Today")

        openStartWorkout(app)
        XCTAssertTrue(app.scrollToHittableAndTap("startWorkout.pick.strength"),
                      "Start Workout did not expose pick Strength")
        XCTAssertTrue(app.navigationBars["Pick Workout"].waitForExistence(timeout: 5),
                      "Pick Strength did not open Pick Workout")
        XCTAssertTrue(app.scrollToHittableAndTap("pickWorkout.previous"),
                      "Pick Workout did not expose previous workouts")
        XCTAssertTrue(app.navigationBars["Previous Workouts"].waitForExistence(timeout: 5),
                      "Previous Workouts route did not open")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Pick Workout"].waitForExistence(timeout: 5),
                      "Returning from Previous Workouts did not restore Pick Workout")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Start Workout"].waitForExistence(timeout: 5),
                      "Returning from Pick Workout did not restore Start Workout")
        XCTAssertTrue(app.buttons["startWorkout.pick.scheduleCardio"].exists,
                      "Start Workout did not expose the separate Schedule Cardio action")
        XCTAssertTrue(app.scrollToHittableAndTap("startWorkout.pick.scheduleCardio"),
                      "Schedule Cardio action was not tappable")
        XCTAssertTrue(app.navigationBars["Schedule Cardio"].waitForExistence(timeout: 5),
                      "Schedule Cardio did not open the shared scheduling picker")
        XCTAssertTrue(app.scrollToHittableAndTap("cardioPicker.schedule.run"),
                      "Schedule Cardio picker did not expose Run")
        XCTAssertTrue(app.navigationBars["Schedule Run"].waitForExistence(timeout: 5),
                      "Selecting a cardio type did not open its date/time scheduler")
        XCTAssertTrue(app.buttons["scheduleWorkout.save"].waitTap(timeout: 5),
                      "Schedule Cardio did not save its date/time")
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Saving Schedule Cardio did not return Home")

        XCTAssertTrue(app.scrollToHittableAndTap("startWorkout.created.strength"),
                      "Start Workout did not generate a personalized workout")
        // Personalized generation is now a single direct transition to the
        // editable plan. Keep the cold-path allowance here because catalog
        // indexing and the solver run off-main and can be slow on CI hosts.
        XCTAssertTrue(app.navigationBars["Workout Plan"].waitForExistence(timeout: 45),
                      "Personalized generation did not open the plan editor")
        XCTAssertFalse(app.staticTexts["Workout unavailable"].exists,
                       "Personalized generation landed on the generic missing-workout warning page")
        XCTAssertFalse(app.navigationBars["View Suggested Workout"].exists,
                       "The retired suggested-workout chooser is still reachable")
        let editableExercises = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "editor.exercise."))
        XCTAssertGreaterThan(editableExercises.count, 0,
                             "Personalized plan did not open in edit mode with exercises")
        XCTAssertTrue(app.buttons["editor.suggestExercise"].waitForExistence(timeout: 5),
                      "Suggested Workout Plan lost Suggest Exercise")
        let editableExerciseInfo = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "editor.exerciseInfo."))
        XCTAssertGreaterThan(editableExerciseInfo.count, 0,
                             "Editable suggested plan does not expose exercise info controls")

        // Real user report: excluding an exercise from a suggested workout
        // left it sitting right there in the plan — excluding only affected
        // *future* suggestions. It must regenerate the whole plan from
        // scratch instead, so the excluded exercise's own row is gone
        // afterward (not merely deleted while everything else stays put).
        let excludeAction = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "editor.exerciseMenu.")).firstMatch
        XCTAssertTrue(excludeAction.waitForExistence(timeout: 5),
                      "Editable suggested plan does not expose an exclude action on its exercises")
        let excludedIdentifier = excludeAction.identifier
        XCTAssertTrue(excludeAction.waitTap(timeout: 5),
                      "Could not open the exclude action for a suggested exercise")
        XCTAssertTrue(app.navigationBars["Exclude Exercise"].waitForExistence(timeout: 5),
                      "Exclude action did not open the exclusion sheet")
        XCTAssertTrue(app.buttons["exclude.confirm"].waitTap(timeout: 5),
                      "Exclude Exercise sheet did not offer to confirm the exclusion")
        // Regeneration is real solver work (rebuilds the candidate vector
        // index), so give it the same cold-simulator latitude as the initial
        // suggested-workout calculation above.
        let excludedRow = app.buttons[excludedIdentifier]
        excludedRow.waitForDisappearance(timeout: 45)
        XCTAssertFalse(excludedRow.exists,
                       "Excluding an exercise from a suggested workout did not regenerate the plan without it")
        XCTAssertFalse(app.alerts["Couldn't rebuild this workout"].exists,
                       "Regenerating the suggested workout after a real exclusion failed unexpectedly")
        XCTAssertGreaterThan(editableExercises.count, 0,
                             "The regenerated suggested plan lost every exercise")
        XCTAssertEqual(app.buttons["editor.edit"].label, "Done",
                       "Suggested workout did not open in edit mode")
        XCTAssertTrue(app.buttons["editor.edit"].waitTap(timeout: 5),
                      "Suggested workout could not switch to read-only mode")
        let previewExercises = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "editor.compactExercise."))
        XCTAssertGreaterThan(previewExercises.count, 0,
                             "Read-only suggested plan preview has no exercises")
        let preservedExerciseIdentifier = previewExercises.firstMatch.identifier
        let previewExerciseInfo = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "editor.exerciseInfo."))
        XCTAssertGreaterThan(previewExerciseInfo.count, 0,
                             "Read-only plan preview does not expose exercise info controls")
        let cleanAndJerk = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "clean and jerk"))
        XCTAssertEqual(cleanAndJerk.count, 0,
                       "Personalized suggestion leaked the Olympic-only Clean and Jerk movement")
        XCTAssertTrue(app.buttons["editor.start"].exists,
                       "Suggested plan editor lacks Start Workout")
        XCTAssertTrue(app.buttons["editor.schedule"].waitForExistence(timeout: 5),
                      "Personalized Workout Plan lost Schedule this Workout")
        XCTAssertEqual(app.buttons["editor.start"].frame.height,
                       app.buttons["editor.schedule"].frame.height,
                       accuracy: 1,
                       "Personalized Schedule this Workout is not the same size as Start Workout")
        XCTAssertTrue(app.buttons["editor.schedule"].waitTap(timeout: 5),
                      "Personalized Workout Plan scheduling did not open")
        XCTAssertTrue(app.navigationBars["Schedule Workout"].waitForExistence(timeout: 5),
                      "Personalized scheduling sheet did not open")
        XCTAssertTrue(app.buttons["scheduleWorkout.save"].waitTap(timeout: 5),
                      "Personalized scheduling sheet did not save")
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Personalized scheduling did not return Home")
        XCTAssertTrue(app.descendants(matching: .any)["home.myWorkouts"].waitForExistence(timeout: 10),
                      "Personalized scheduling did not render My Workouts")

        let scheduledStart = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "home.planned.start.")).firstMatch
        XCTAssertTrue(scheduledStart.waitTap(timeout: 10),
                      "Personalized scheduled workout could not be started")
        XCTAssertTrue(app.navigationBars["Workout Plan"].waitForExistence(timeout: 10),
                      "Starting a personalized scheduled workout did not preserve the plan view")
        XCTAssertTrue(app.descendants(matching: .any)[preservedExerciseIdentifier]
                        .waitForExistence(timeout: 5),
                      "Starting the scheduled workout lost its exact exercise payload")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Returning from the scheduled workout did not land on Home")

        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Home inline Start Workout did not reopen after suggested workouts")
        openStartWorkout(app)
        expandAllCardioIfNeeded(app)

        // Field test 2026-08-20 issue 8: Rowing remains in the expanded cardio
        // taxonomy, which now uses three columns.
        XCTAssertTrue(app.scrollToElement("cardioPicker.start.rowing"),
                      "Start Workout did not offer Rowing")
        let cycle = app.buttons["cardioPicker.start.cycle"]
        XCTAssertTrue(cycle.exists, "Start Workout lost Cycle")
        let run = app.buttons["cardioPicker.start.run"]
        XCTAssertTrue(run.exists, "Start Workout lost Run")
        XCTAssertEqual(run.frame.width, run.frame.height, accuracy: 2,
                       "Compact cardio tiles are not square")
        XCTAssertGreaterThan(app.buttons["cardioPicker.showMore"].frame.height, 40,
                             "Cardio Show more does not have a usable hit area")
        let rowing = app.buttons["cardioPicker.start.rowing"]
        XCTAssertGreaterThan(rowing.frame.minX, cycle.frame.minX,
                             "Rowing is not after Cycle in the cardio grid")
        let swim = app.buttons["cardioPicker.start.swim"]
        XCTAssertTrue(swim.exists, "Start Workout lost Swim")
        XCTAssertLessThan(rowing.frame.minY, swim.frame.minY,
                          "Rowing is not before Swim in the cardio grid")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openStartWorkout(app)
        XCTAssertTrue(app.scrollToHittableAndTap("startWorkout.pick.strength"),
                      "Start Workout did not offer pick Strength")
        XCTAssertTrue(app.navigationBars["Pick Workout"].waitForExistence(timeout: 5),
                      "Pick Strength did not open Pick Workout")
        XCTAssertTrue(app.scrollToHittableAndTap("pickWorkout.custom"),
                      "Pick Workout did not offer Custom Workout")
        XCTAssertTrue(app.buttons["editor.start"].waitForExistence(timeout: 10),
                      "Custom workout did not open the Workout Plan editor")
        XCTAssertFalse(app.buttons["editor.generate"].exists,
                       "Custom Workout still exposes the non-functional Generate with Coach action")
        XCTAssertTrue(app.buttons["editor.start"].label.contains("Start Workout"),
                      "Workout Plan start action is not labeled Start Workout")
        XCTAssertTrue(app.buttons["editor.addExercise"].waitForExistence(timeout: 5),
                      "Custom Workout did not open in edit mode")
        XCTAssertTrue(app.buttons["editor.suggestExercise"].waitForExistence(timeout: 5),
                      "Custom Workout Plan lost Suggest Exercise")
        // Field test 2026-08-18 #5: the plan editor is a Home-rhythm scroll surface.
        XCTAssertTrue(app.descendants(matching: .any)["editor.partners"].waitForExistence(timeout: 5),
                      "Workout Plan lost its Training partners card")

        // Field test 2026-08-18 #4: a partner is addable from the plan itself —
        // no Edit mode — and the coach immediately fills THEIR plan for the
        // owner's exercise. Unguarded: every step below fails if it is missing.
        XCTAssertTrue(app.buttons["editor.addExercise"].waitTap(timeout: 5),
                      "Plan editor did not offer Add Exercise")
        // Exercise-level progression is reachable from the same picker used to
        // add a movement. Keep this in the single iPhone smoke path so the
        // drill-down cannot silently disappear while the normal add flow still
        // passes.
        let pickerRow = app.buttons["picker.row.\(exerciseName)"]
        let pickerSearch = app.searchFields.firstMatch
        XCTAssertTrue(pickerSearch.waitForExistence(timeout: 10),
                      "Exercise picker did not expose search")
        pickerSearch.tap()
        pickerSearch.typeText(exerciseName)
        XCTAssertTrue(pickerRow.waitTap(timeout: 10),
                      "Exercise picker did not expose \(exerciseName)")
        XCTAssertTrue(app.buttons["exercise.progress.open"].waitTap(timeout: 10),
                      "Exercise detail did not expose View Progress")
        XCTAssertTrue(app.navigationBars["Exercise Progress"].waitForExistence(timeout: 10),
                      "Exercise Progress did not open from exercise detail")
        XCTAssertTrue(app.descendants(matching: .any)["exercise.progress.summary"]
                        .waitForExistence(timeout: 5),
                      "Exercise Progress did not render its summary")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Add Exercise"].waitForExistence(timeout: 5),
                      "Exercise Progress did not return to the picker")
        XCTAssertTrue(app.buttons["picker.row.\(exerciseName)"].waitTap(timeout: 10),
                      "Exercise picker did not reopen exercise detail")
        XCTAssertTrue(app.buttons["detail.add"].waitTap(timeout: 10),
                      "Exercise detail did not return the selected exercise")
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
        XCTAssertTrue(app.descendants(matching: .any)["plan.volume.performers"].exists,
                      "Workout Plan volume did not expose the partner picker")
        XCTAssertTrue(app.buttons["plan.volume.performer.owner"].exists,
                      "Workout Plan volume did not expose the owner choice")

        // One-off scheduling is the only planning surface now. It must sit
        // directly under Start Workout, use the same control height, persist
        // the reviewed custom snapshot, and return to Home without exposing a
        // weekly planner.
        XCTAssertTrue(app.buttons["editor.schedule"].waitForExistence(timeout: 5),
                      "Custom Workout Plan lost Schedule this Workout")
        XCTAssertEqual(app.buttons["editor.start"].frame.height,
                       app.buttons["editor.schedule"].frame.height,
                       accuracy: 1,
                       "Schedule this Workout is not the same size as Start Workout")
        XCTAssertTrue(app.buttons["editor.schedule"].waitTap(timeout: 5),
                      "Schedule this Workout did not open")
        XCTAssertTrue(app.navigationBars["Schedule Workout"].waitForExistence(timeout: 5),
                      "Schedule Workout sheet did not open")
        XCTAssertTrue(app.buttons["scheduleWorkout.save"].waitTap(timeout: 5),
                      "Schedule Workout sheet did not save")
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Saving a scheduled workout did not return Home")
        XCTAssertTrue(app.descendants(matching: .any)["home.myWorkouts"].waitForExistence(timeout: 10),
                      "Home did not render My Workouts")
        XCTAssertTrue(app.scrollToElement("home.myWorkouts.showMore"),
                      "My Workouts did not offer the today/future detail view")
        XCTAssertTrue(app.scrollToHittableAndTap("home.myWorkouts.showMore"),
                      "My Workouts Show more did not open Planned Workouts")
        XCTAssertTrue(app.navigationBars["Planned Workouts"].waitForExistence(timeout: 10),
                      "My Workouts Show more did not open the Planned Workouts list")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Returning from Planned Workouts did not land on Home")

        XCTAssertFalse(app.buttons["tab.plan"].exists,
                       "Retired Plan tab is still exposed")

        XCTAssertTrue(app.startEmptyStrengthWorkout(), "Quick Start did not enter the workout")
        XCTAssertFalse(app.buttons["editor.showSettings"].exists,
                       "Quick Start unexpectedly opened workout settings")
        XCTAssertTrue(app.buttons["session.suggestExercise"].waitForExistence(timeout: 5),
                      "Active workout lost Suggest Exercise")

        // Field test 2026-08-18 §5b: the flow logs real sets with a partner, the
        // way the watch smoke test does. Without this every summary assertion
        // below is vacuous — the session would contain no exercises at all.
        XCTAssertTrue(app.addSessionPartner("Sam"), "Could not add a training partner to the session")
        XCTAssertTrue(app.pickExercise(exerciseName),
                      "Could not add \(exerciseName) to the live session")
        XCTAssertTrue(app.saveSetInEditor(), "Owner's set did not save")
        // Field test 2026-08-19 #6: saving returns to the workout with that
        // exercise still expanded, so the next set is one tap away.
        XCTAssertTrue(app.buttons["set.add.\(exerciseName)"].waitForExistence(timeout: 10),
                      "Saving a set collapsed the exercise instead of leaving it open")
        app.dismissRestBar()

        // Field test 2026-08-27 issue 1: after the owner's set saves, reopening
        // Add Set must advance to Sam even when the pending owner row leads.
        XCTAssertTrue(app.scrollToHittableAndTap("set.add.\(exerciseName)"),
                      "Could not reopen the set editor for the next set")
        XCTAssertTrue(app.descendants(matching: .any)["setEditor.history"]
                        .waitForExistence(timeout: 10),
                      "Set editor is missing the History card")
        let samNoHistory = app.descendants(matching: .any)["setEditor.history.noHistory"]
        XCTAssertTrue(samNoHistory.waitForExistence(timeout: 5),
                      "Add Set did not advance to Sam after the owner's set")
        XCTAssertTrue(samNoHistory.label.contains("Sam"),
                      "The next Add Set editor did not name Sam as the selected performer")
        XCTAssertTrue(app.buttons["setEditor.performer"].waitTap(timeout: 10),
                      "Set editor lost the Who did this set? picker")
        let me = app.buttons.containing(NSPredicate(format: "label == %@", "Me")).firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 5), "Me is not in the performer picker")
        me.tap()
        let ownerLastSet = app.descendants(matching: .any)["setEditor.history.lastSet"]
        XCTAssertTrue(ownerLastSet.waitForExistence(timeout: 5),
                      "Switching back to Me did not show the owner's just-saved set")
        XCTAssertTrue(ownerLastSet.label.contains("× 5"),
                      "Last set today does not carry the owner's just-logged reps (default 5)")
        XCTAssertTrue(app.buttons["setEditor.performer"].waitTap(timeout: 10),
                      "Set editor lost the Who did this set? picker after switching to Me")
        let sam = app.buttons.containing(NSPredicate(format: "label == %@", "Sam")).firstMatch
        XCTAssertTrue(sam.waitForExistence(timeout: 5), "Sam is not in the performer picker")
        sam.tap()
        XCTAssertFalse(app.descendants(matching: .any)["setEditor.history.lastSet"].exists,
                       "Switching to Sam left the owner's last set on the History card")
        XCTAssertTrue(samNoHistory.waitForExistence(timeout: 5),
                      "Sam's History card does not say No previous history")
        XCTAssertTrue(samNoHistory.label.contains("Sam"),
                      "No previous history does not name the selected performer")
        // The Cancel button exists twice in the tree (toolbar + footer share the
        // id), so firstMatch resolves it, as with confirmation-dialog buttons.
        let cancel = app.buttons.matching(identifier: "setEditor.cancel").firstMatch
        XCTAssertTrue(cancel.waitTap(timeout: 5),
                      "Set editor Cancel did not dismiss")

        XCTAssertTrue(app.logPartnerSet(exercise: exerciseName, partner: "Sam"),
                      "Partner's set did not save")
        app.dismissRestBar()

        XCTAssertTrue(app.scrollToHittableAndTap("workout.end"), "End workout button did not tap")
        let end = app.dialogButton("workout.endConfirm")
        XCTAssertTrue(end.waitForExistence(timeout: 5), "End confirmation did not appear")
        end.tap()

        XCTAssertTrue(app.descendants(matching: .any)["summary.title"].waitForExistence(timeout: 15),
                      "post-workout summary did not render")
        XCTAssertTrue(app.descendants(matching: .any)["summary.volumeSummary"].waitForExistence(timeout: 10),
                      "post-workout summary did not render the workout volume section")
        XCTAssertTrue(app.descendants(matching: .any)["summary.volume.performers"].waitForExistence(timeout: 5),
                      "Post-workout volume did not expose the partner picker")
        XCTAssertTrue(app.buttons["summary.volume.performer.owner"].exists,
                      "Post-workout volume did not expose the owner choice")
        let summarySamVolume = app.buttons["summary.volume.performer.summary.Sam"]
        XCTAssertTrue(summarySamVolume.exists,
                      "Post-workout volume did not expose Sam's choice")
        XCTAssertTrue(summarySamVolume.waitTap(timeout: 5),
                      "Post-workout volume could not switch to Sam")

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
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Home did not return after summary")

        // Field test 2026-08-18 #6: the finished workout is a tappable My
        // Workouts row.
        let todayRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'home.today.row.'")).firstMatch
        XCTAssertTrue(todayRow.waitForExistence(timeout: 10),
                      "Completed workout did not appear in My Workouts")

        // This Week no longer duplicates History. The canonical History surface
        // remains reachable from Progress, while Sets keeps the partner filter.
        XCTAssertTrue(app.buttons["tab.thisWeek"].waitTap(timeout: 10),
                      "Could not open This Week for the partner volume check")
        XCTAssertTrue(app.scrollToHittableAndTap("home.week.sets.showMore"),
                      "This Week did not expose its Sets disclosure after partner work")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.sets.performers"]
                        .waitForExistence(timeout: 5),
                      "This Week Sets did not expose the partner picker")
        XCTAssertTrue(app.buttons["home.week.sets.performer.owner"].exists,
                      "This Week Sets did not expose the owner choice")
        XCTAssertFalse(app.descendants(matching: .any)["home.myHistory"].exists,
                       "This Week still rendered the retired My History section")
        XCTAssertTrue(app.buttons["tab.progress"].waitTap(timeout: 10),
                      "Could not open Progress for full History")
        XCTAssertTrue(app.scrollToHittableAndTap("progress.fullHistory"),
                      "Progress did not offer View full history")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 10),
                      "Progress full-history action did not open History")
        XCTAssertTrue(app.buttons["session.row"].waitForExistence(timeout: 10),
                      "Full History did not show the completed workout")
        app.buttons["session.row"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["summary.title"].waitForExistence(timeout: 10),
                      "History workout row did not open its summary")
        XCTAssertTrue(app.descendants(matching: .any)["summary.volumeSummary"].waitForExistence(timeout: 10),
                      "History summary did not render the workout volume section")
        XCTAssertTrue(app.buttons["summary.back"].waitTap(timeout: 5),
                      "History summary did not expose the Phase 8 Back action")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 10),
                      "Summary Back did not return to full History")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["tab.today"].waitTap(timeout: 10),
                      "Could not return to Today after full History")
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Returning from full History did not land on Today")

        // Field test 2026-08-20 issue 5: ending a cardio workout must stop the
        // watch's workout session — the leak behind the "live activity that never
        // stops". Under -uiTestWatchStop every stopWatchWorkout() call lands in
        // uitest.watchStopCount, so the counter read right before the End button
        // proves the cardio terminal path itself stops the watch. The HR gate's
        // Continue must also be enabled on a fresh cardio start (P6's regression,
        // asserted here while the screen is in front of us).
        XCTAssertTrue(app.buttons["tab.today"].waitTap(timeout: 10),
                      "Could not return to Today for the cardio flow")
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Home inline Start Workout did not reopen for the cardio flow")
        openStartWorkout(app)
        XCTAssertTrue(app.scrollToHittableAndTap("startWorkout.pick.cardio"),
                      "Start Workout did not offer Pick Your Own Cardio")
        XCTAssertTrue(app.navigationBars["Cardio"].waitForExistence(timeout: 5),
                      "Pick Your Own Cardio did not open the Cardio picker")
        XCTAssertTrue(app.scrollToHittableAndTap("cardioPicker.start.run"),
                      "Start Workout did not offer the Run cardio tile")
        XCTAssertTrue(app.scrollToHittableAndTap("goal.none"),
                      "Cardio goal sheet did not offer start-without-goal")
        let continueButton = app.buttons["prehr.start"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10),
                      "HR gate did not appear before the cardio workout")
        XCTAssertTrue(app.buttons["prehr.cancel"].exists,
                      "HR gate did not offer a way back to Home")
        XCTAssertTrue(continueButton.isEnabled,
                      "HR gate Continue is disabled on a fresh cardio start")
        continueButton.tap()
        app.skipCountdown()
        XCTAssertTrue(app.scrollToHittableAndTap("outdoor.end"),
                      "Outdoor cardio did not offer End")
        let stopsBeforeEnd = app.watchStopCount()
        XCTAssertGreaterThan(stopsBeforeEnd, 0,
                             "No watch stop was recorded before the cardio ended")
        XCTAssertTrue(app.dialogButton("workout.endConfirm").waitTap(timeout: 5),
                      "Cardio end confirmation did not appear")
        XCTAssertTrue(app.descendants(matching: .any)["summary.title"].waitForExistence(timeout: 15),
                      "Cardio workout did not reach its summary")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(timeout: 10),
                      "Cardio summary Done did not dismiss")
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 10),
                      "Home did not return after the cardio summary")
        XCTAssertGreaterThan(app.watchStopCount(), stopsBeforeEnd,
                             "Ending the cardio workout did not stop the watch workout session")

        // Persistence safety smoke check: the completed workout must remain in
        // the local store across the same terminate/relaunch boundary users hit
        // when unlocking or updating the app. The unique store id prevents this
        // test from reading another simulator run's fixtures.
        app.terminate()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground,
                       "App did not relaunch after the workout was persisted")
        XCTAssertTrue(app.descendants(matching: .any)["home.startWorkout"].waitForExistence(timeout: 15),
                      "Home did not load after relaunch")
        XCTAssertTrue(app.descendants(matching: .any)
                        .matching(NSPredicate(format: "identifier BEGINSWITH 'home.today.row.'"))
                        .firstMatch.waitForExistence(timeout: 15),
                      "Completed workout disappeared from Workouts Today after relaunch")
    }
    private func openStartWorkout(_ app: XCUIApplication) {
        if app.navigationBars["Start Workout"].exists { return }
        XCTAssertTrue(app.scrollToHittableAndTap("selectWorkout.startWorkout"),
                      "Today is missing Start Workout")
        XCTAssertTrue(app.navigationBars["Start Workout"].waitForExistence(timeout: 5),
                      "Start Workout did not open")
    }

    private func expandAllCardioIfNeeded(_ app: XCUIApplication) {
        if app.buttons["startWorkout.pick.cardio"].exists {
            XCTAssertTrue(app.scrollToHittableAndTap("startWorkout.pick.cardio"),
                          "Start Workout did not expose Pick Your Own Cardio")
            XCTAssertTrue(app.navigationBars["Cardio"].waitForExistence(timeout: 5),
                          "Pick Your Own Cardio did not open the Cardio Picker")
        }
        let disclosure = app.buttons["cardioPicker.showMore"]
        XCTAssertTrue(app.scrollToElement("cardioPicker.showMore"),
                      "Cardio Picker did not expose Show more")
        if (disclosure.value as? String) != "Expanded" {
            XCTAssertTrue(disclosure.waitTap(timeout: 5), "Show more cardio did not expand")
        }
    }

}
