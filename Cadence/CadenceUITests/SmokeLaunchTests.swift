import XCTest

/// The one normal iPhone XCUITest. It covers the minimum end-to-end surface that
/// needs a real simulator: launch, planning, starting, logging, ending, and the
/// post-workout summary. Everything else belongs in headless `swift test`.
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

        XCTAssertTrue(app.scrollToHittableAndTap("tab.plan"), "Plan tab did not open")
        XCTAssertTrue(app.descendants(matching: .any)["planning"].waitForExistence(timeout: 10),
                      "Programs screen did not render")
        app.popToHome()

        XCTAssertTrue(app.openQuickStartStrengthEditor(), "Quick Start editor did not open")
        XCTAssertTrue(app.buttons["editor.edit"].waitForExistence(timeout: 5),
                      "Workout Plan did not show its Edit action")
        XCTAssertFalse(app.buttons["editor.addExercise"].exists,
                       "Workout Plan entered edit mode by default")
        XCTAssertTrue(app.buttons["editor.showSettings"].waitTap(timeout: 5),
                      "Workout settings popup did not open")
        XCTAssertTrue(app.descendants(matching: .any)["editor.settingsSheet"].waitForExistence(timeout: 5),
                      "Workout settings popup did not render")
        XCTAssertTrue(app.navigationBars["Workout Settings"].buttons["Done"].waitTap(timeout: 5),
                      "Workout settings popup did not dismiss")
        XCTAssertTrue(app.buttons["editor.edit"].waitTap(timeout: 5),
                      "Workout Plan Edit action did not activate editing")
        XCTAssertTrue(app.addExerciseToOpenWorkoutPlan("Bench Press"),
                      "could not add Bench Press to the workout plan")

        let editorStart = app.buttons["editor.start"].exists
            ? app.buttons["editor.start"]
            : app.descendants(matching: .any)["editor.start"]
        XCTAssertTrue(editorStart.waitTap(timeout: 10), "planned workout did not start")
        XCTAssertTrue(app.buttons["set.add.Bench Press"].waitTap(timeout: 25),
                      "planned Bench Press card did not render")

        XCTAssertTrue(app.descendants(matching: .any)["setEditor.fullScreen"].waitForExistence(timeout: 10),
                      "expanded set editor did not open")
        XCTAssertTrue(app.descendants(matching: .any)["setEditor.exerciseName"].waitForExistence(timeout: 5),
                      "expanded editor did not show exercise name")
        XCTAssertTrue(app.descendants(matching: .any)["setEditor.setNumber"].waitForExistence(timeout: 5),
                      "expanded editor did not show set number")

        XCTAssertTrue(app.buttons["setEditor.weight.increment.5"].waitTap(timeout: 5),
                      "5 lb increment was not available")
        XCTAssertTrue(app.buttons["setEditor.weight.plus"].waitTap(timeout: 5),
                      "weight plus control did not tap")
        XCTAssertGreaterThanOrEqual(app.buttons["setEditor.weight.plus"].frame.height, 44,
                                    "weight plus hit target is too small")
        let weightAccessibilityValue = app.buttons["setEditor.weightValue"].value as? String
        XCTAssertTrue(weightAccessibilityValue == "5 kg" || weightAccessibilityValue == "5 lb",
                      "weight accessibility value did not update: \(weightAccessibilityValue ?? "nil")")
        app.swipeUp()
        XCTAssertTrue(app.buttons["setEditor.reps.minus"].waitTap(timeout: 5),
                      "reps decrement did not tap")
        XCTAssertTrue(app.buttons["setEditor.reps.plus"].waitTap(timeout: 5),
                      "reps increment did not tap")
        XCTAssertTrue(app.buttons["setEditor.effort.rir"].waitTap(timeout: 5),
                      "RIR mode did not tap")
        XCTAssertTrue(app.buttons["setEditor.effort.value.2"].waitTap(timeout: 5),
                      "RIR value did not tap")
        XCTAssertTrue(app.buttons["setEditor.save"].waitTap(timeout: 10),
                      "Save set did not tap")

        // The set must land as a completed row on the card.
        XCTAssertTrue(app.buttons["set.editWeight.Bench Press.1"].waitForExistence(timeout: 10),
                      "logged set row did not appear")
        XCTAssertEqual(app.descendants(matching: .any)["set.editRPE.Bench Press.1"].label, "RPE 8",
                       "RIR selection did not persist as canonical RPE")
        XCTAssertTrue(app.buttons["exercise.edit.Bench Press"].waitTap(timeout: 5),
                      "set edit mode did not open")
        XCTAssertTrue(app.buttons["set.editWeight.Bench Press.1"].waitTap(timeout: 5),
                      "completed set did not open expanded editor")
        XCTAssertTrue(app.descendants(matching: .any)["setEditor.fullScreen"].waitForExistence(timeout: 5),
                      "edit did not use expanded editor")
        XCTAssertTrue(app.buttons["setEditor.weight.increment.0.25"].waitTap(timeout: 5),
                      "quarter-pound increment was not available")
        XCTAssertTrue(app.buttons["setEditor.weight.plus"].waitTap(timeout: 5),
                      "quarter-pound adjustment did not tap")
        XCTAssertTrue(app.buttons["setEditor.save"].waitTap(timeout: 10),
                      "Save changes did not tap")
        XCTAssertTrue(app.descendants(matching: .any)["set.row.Bench Press.1"].waitForExistence(timeout: 10),
                      "edited set row did not remain present")
        XCTAssertTrue(app.buttons["exercise.edit.Bench Press"].waitTap(timeout: 5),
                      "set edit mode did not close")

        XCTAssertTrue(app.buttons["set.add.Bench Press"].waitTap(timeout: 5),
                      "fresh Add Set did not open")
        XCTAssertTrue(app.descendants(matching: .any)["setEditor.fullScreen"].waitForExistence(timeout: 5),
                      "fresh set did not use expanded editor")
        XCTAssertTrue(app.buttons["setEditor.weight.plus"].waitTap(timeout: 5),
                      "fresh-set weight adjustment did not tap")
        XCTAssertTrue(app.buttons.matching(identifier: "setEditor.cancel").firstMatch.waitTap(timeout: 5),
                      "expanded editor cancel did not tap")
        XCTAssertFalse(app.buttons["set.row.Bench Press.2"].waitForExistence(timeout: 3),
                       "cancel unexpectedly added a second set")
        app.dismissRestBar()

        XCTAssertTrue(app.scrollToHittableAndTap("workout.end"), "End workout button did not tap")
        let end = app.dialogButton("workout.endConfirm")
        XCTAssertTrue(end.waitForExistence(timeout: 5), "End confirmation did not appear")
        end.tap()

        XCTAssertTrue(app.descendants(matching: .any)["summary.title"].waitForExistence(timeout: 15),
                      "post-workout summary did not render")
        XCTAssertTrue(app.descendants(matching: .any)["summary.metric.sets"].waitForExistence(timeout: 5),
                      "summary did not show set count")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(timeout: 10), "summary Done did not tap")
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 10),
                      "Home did not return after summary")
    }
}
