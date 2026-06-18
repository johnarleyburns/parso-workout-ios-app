import XCTest

/// strength-pivot P5.3 — Coach Workout is now inside the Strength start flow
/// (WeightsStartView). Tapping it materializes the prescription into a logger
/// session pre-filled with the prescribed movement, sets/reps, and working load.
final class P5DoThisUITests: CadenceUITestCase {

    func testDoThisPreFillsPrescribedLiftAndLoad() {
        let app = XCUIApplication.launched(seeds: ["history"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start")
        XCTAssertTrue(app.buttons["startType.weights"].waitTap(), "Strength type")
        XCTAssertTrue(app.buttons["weights.coachStart"].waitTap(), "Coach Workout")
        XCTAssertTrue(app.buttons["editor.start"].waitTap(), "Start from editor")

        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25),
                      "the prescription opens the logger")

        let planned = app.descendants(matching: .any)["exerciseCard.Back Squat"]
        XCTAssertTrue(planned.waitForExistence(timeout: 5), "prescribed movement pre-loaded")
        let rx = app.descendants(matching: .any)["session.rx.Back Squat"].firstMatch
        XCTAssertTrue(rx.waitForExistence(timeout: 5), "prescription line shown")
        XCTAssertTrue((rx.label).contains("@"), "the prescription line carries the working load")

        app.buttons["set.add.Back Squat"].tap()
        let weight = app.staticTexts["set.weight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 10), "weight keypad")
        let entry = (weight.value as? String) ?? ""
        XCTAssertFalse(entry.isEmpty, "the keypad weight is pre-filled with the prescribed load")
        XCTAssertNotEqual(entry, "0", "the prescribed load is non-zero")
    }

    func testDoThisColdStartOpensSession() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start")
        XCTAssertTrue(app.buttons["startType.weights"].waitTap(), "Strength type")
        XCTAssertTrue(app.buttons["weights.coachStart"].waitTap(), "Coach Workout")
        XCTAssertTrue(app.buttons["editor.start"].waitTap(), "Start from editor")
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25),
                      "the starter prescription opens the logger")
    }
}
