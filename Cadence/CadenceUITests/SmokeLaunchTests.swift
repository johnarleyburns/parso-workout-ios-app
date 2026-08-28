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
        // set for someone other than the owner (field test 2026-08-18 §5b). The
        // watch-stop seam makes the cardio end below provable, not vacuous.
        let app = XCUIApplication.launched(seeds: ["person.Sam"],
                                           extraArgs: ["-uiTestWatchStop"])

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
        XCTAssertTrue(app.staticTexts["Observations"].waitForExistence(timeout: 5),
                      "Coach's Suggestions heading was not renamed to Observations")
        XCTAssertFalse(app.staticTexts["Coach’s Suggestions"].exists)
        XCTAssertFalse(app.staticTexts["Coach's Suggestions"].exists)
        XCTAssertFalse(app.staticTexts["Coach's Workout"].exists)
        XCTAssertFalse(app.staticTexts["Do Coach's Workout"].exists)
        let cta = app.buttons["home.suggestWorkout"]
        XCTAssertTrue(cta.waitForExistence(timeout: 5),
                      "Suggest a Workout is missing below the observations card")
        XCTAssertEqual(cta.frame.height, app.buttons["home.startWorkout"].frame.height,
                       accuracy: 1,
                       "Suggest a Workout does not match Home Start Workout's height")
        XCTAssertGreaterThan(cta.frame.minY,
                             app.descendants(matching: .any)["home.observations.card"].frame.minY,
                             "Suggest a Workout is not below the Observations card")
        XCTAssertFalse(app.buttons["home.coachRecommendation.preview"].exists,
                       "Coach card still exposes the removed Preview Workout action")

        XCTAssertTrue(app.scrollToHittableAndTap("home.week.showMore"),
                      "This Week did not offer Show more")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.volumeHeading"].waitForExistence(timeout: 5),
                      "This Week did not expand in place")
        XCTAssertTrue(app.scrollToHittableAndTap("home.volume.quadriceps"),
                      "Expanded This Week did not expose the Quads volume row")
        let quadsVolume = app.descendants(matching: .any)["home.volume.quadriceps"]
        XCTAssertTrue((quadsVolume.value as? String)?.contains("0 sets, Below 4-set minimum") == true,
                      "A zero-set muscle group is not exposed as below the red-facing minimum")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.volumeHeading"].exists,
                      "Expanded This Week did not label the muscle-group rows as Volume")
        // DB++ adoption: Volume carries the per-muscle-group breakdown, and the
        // redundant Muscles row and section are gone.
        XCTAssertTrue(app.descendants(matching: .any)["home.volume.chest"].exists,
                      "Volume does not list every tracked muscle group")
        XCTAssertTrue(app.descendants(matching: .any)["home.volume.lats"].exists,
                      "Volume does not list muscle groups the old body parts hid")
        XCTAssertFalse(app.descendants(matching: .any)["home.week.muscles"].exists,
                       "The redundant Muscles breakdown is still on Home")
        XCTAssertFalse(app.descendants(matching: .any)["home.muscle.chest"].exists,
                       "The old per-muscle row identifiers are still present")
        XCTAssertTrue(app.descendants(matching: .any)["home.week.cardioMinutes"].exists,
                      "Expanded This Week does not explain the moderate-equivalent cardio total")
        XCTAssertTrue(app.descendants(matching: .any)["progress.card.citation"].exists,
                      "Weekly volume does not expose a navigable science link")
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
        if app.buttons["home.observations.showMore"].exists {
            XCTAssertTrue(app.scrollToHittableAndTap("home.observations.showMore"),
                          "Observations did not show only the first warning before Show more...")
            XCTAssertTrue(app.scrollToHittableAndTap("home.observations.showLess"),
                          "Observations did not put Show less at the bottom")
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
        let coach = app.buttons["selectWorkout.suggestWorkout"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5), "Start Workout lost Quick Start")
        let quickHeight = quick.frame.height
        XCTAssertEqual(quickHeight, custom.frame.height, accuracy: 1,
                       "Quick Start and Custom Workout are different heights")
        if coach.exists {
            XCTAssertTrue(coach.label.contains("Suggest a Workout"),
                          "Suggested-workout action still uses the old visible label")
            XCTAssertFalse(app.buttons["selectWorkout.coach"].exists)
            XCTAssertEqual(quickHeight, coach.frame.height, accuracy: 1,
                           "Suggest a Workout is a different height from Quick Start")
        }

        XCTAssertTrue(app.scrollToHittableAndTap("selectWorkout.suggestWorkout"),
                      "Start Workout did not open suggested workouts")
        XCTAssertTrue(app.descendants(matching: .any)["suggestedWorkout.ready"].waitForExistence(timeout: 15),
                      "Suggested workouts did not become ready")
        XCTAssertTrue(app.navigationBars["View Suggested Workout"].exists,
                      "Suggested-workout chooser has the wrong title")
        // Five training styles at one set target, not three lengths of the same
        // workout (DB++ adoption, decision D6).
        let fitness = app.buttons["suggestedWorkout.style.fitness"]
        let bodyweight = app.buttons["suggestedWorkout.style.bodyweight"]
        let powerlifting = app.buttons["suggestedWorkout.style.powerlifting"]
        let olympic = app.buttons["suggestedWorkout.style.olympic"]
        let strongman = app.buttons["suggestedWorkout.style.strongman"]
        XCTAssertTrue(fitness.exists)
        XCTAssertTrue(bodyweight.exists)
        XCTAssertTrue(powerlifting.exists)
        XCTAssertEqual(fitness.label, "Fitness")
        XCTAssertEqual(bodyweight.label, "Bodyweight")
        XCTAssertEqual(powerlifting.label, "Powerlifting")
        XCTAssertLessThan(fitness.frame.minY, bodyweight.frame.minY)
        XCTAssertLessThan(bodyweight.frame.minY, powerlifting.frame.minY)
        XCTAssertTrue(app.scrollToElement("suggestedWorkout.style.olympic"))
        XCTAssertEqual(olympic.label, "Olympic Weightlifting")
        XCTAssertTrue(app.scrollToElement("suggestedWorkout.style.strongman"))
        XCTAssertEqual(strongman.label, "Strongman")
        XCTAssertFalse(app.buttons["suggestedWorkout.minimum"].exists,
                       "The retired minimum/medium/maximal tiers are still on screen")
        XCTAssertTrue(app.scrollToElement("suggestedWorkout.science.iversenTimeEfficient2021"),
                      "Chooser result does not expose the Iversen citation link")
        XCTAssertTrue(app.scrollToElement("suggestedWorkout.science.pellandFractionalSets2024"),
                      "Chooser result does not expose the Pelland citation link")
        XCTAssertTrue(app.buttons["suggestedWorkout.about"].waitTap(timeout: 5),
                      "Suggested-workout chooser lacks its About button")
        XCTAssertTrue(app.staticTexts["No Time to Lift? Designing Time-Efficient Training Programs for Strength and Hypertrophy: A Narrative Review"].waitForExistence(timeout: 5),
                      "About suggested workouts does not show the Iversen study title")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "The Resistance Training Dose-Response")).firstMatch.exists,
                      "About suggested workouts does not show the Pelland study title")
        XCTAssertTrue(app.scrollToElement("suggestedWorkout.about.science.iversenTimeEfficient2021"))
        XCTAssertTrue(app.scrollToElement("suggestedWorkout.about.science.pellandFractionalSets2024"),
                      "About suggested workouts does not expose both science links")
        XCTAssertTrue(app.scrollToElement("suggestedWorkout.about.style.strongman"),
                      "About suggested workouts does not explain what each style is")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["suggestedWorkout.style.fitness"].waitTap(timeout: 5),
                      "The Fitness plan did not open")
        XCTAssertTrue(app.navigationBars["Workout Plan"].waitForExistence(timeout: 10),
                      "The Fitness plan did not open the plan editor")
        XCTAssertTrue(app.buttons["editor.start"].exists,
                      "Suggested plan editor lacks Start Workout")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["View Suggested Workout"].waitForExistence(timeout: 5),
                      "Back did not return to suggested workouts")
        app.navigationBars["View Suggested Workout"].swipeDown()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 10),
                      "Suggested-workout sheet did not swipe-dismiss back to Home")

        XCTAssertTrue(app.scrollToHittableAndTap("home.startWorkout"),
                      "Home Start Workout did not reopen after suggested workouts")

        // Field test 2026-08-20 issue 8: Rowing is a cardio box in the entry
        // taxonomy, placed after Cycle in the cardio grid. The 2-column grid
        // renders Cycle + Rowing on the same row (Cycle left, Rowing right), so
        // "after Cycle" is a horizontal comparison; Rowing must also sit above
        // the next row (Swim).
        XCTAssertTrue(app.scrollToElement("startType.rowing"),
                      "Start Workout did not offer Rowing")
        let cycle = app.buttons["startType.cycle"]
        XCTAssertTrue(cycle.exists, "Start Workout lost Cycle")
        let rowing = app.buttons["startType.rowing"]
        XCTAssertGreaterThan(rowing.frame.minX, cycle.frame.minX,
                             "Rowing is not after Cycle in the cardio grid")
        let swim = app.buttons["startType.swim"]
        XCTAssertTrue(swim.exists, "Start Workout lost Swim")
        XCTAssertLessThan(rowing.frame.minY, swim.frame.minY,
                          "Rowing is not before Swim in the cardio grid")
        // Return to the top of the sheet for the strength-flow steps that follow.
        app.scrollViews.firstMatch.swipeDown()
        app.scrollViews.firstMatch.swipeDown()

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

        // Field test 2026-08-20 issue 5: ending a cardio workout must stop the
        // watch's workout session — the leak behind the "live activity that never
        // stops". Under -uiTestWatchStop every stopWatchWorkout() call lands in
        // uitest.watchStopCount, so the counter read right before the End button
        // proves the cardio terminal path itself stops the watch. The HR gate's
        // Continue must also be enabled on a fresh cardio start (P6's regression,
        // asserted here while the screen is in front of us).
        XCTAssertTrue(app.scrollToHittableAndTap("home.startWorkout"),
                      "Home Start Workout did not reopen for the cardio flow")
        XCTAssertTrue(app.scrollToHittableAndTap("startType.run"),
                      "Start Workout did not offer the Run cardio tile")
        XCTAssertTrue(app.scrollToHittableAndTap("goal.none"),
                      "Cardio goal sheet did not offer start-without-goal")
        let continueButton = app.buttons["prehr.start"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10),
                      "HR gate did not appear before the cardio workout")
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
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 10),
                      "Home did not return after the cardio summary")
        XCTAssertGreaterThan(app.watchStopCount(), stopsBeforeEnd,
                             "Ending the cardio workout did not stop the watch workout session")
    }
}
