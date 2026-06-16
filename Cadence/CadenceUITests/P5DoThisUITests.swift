import XCTest

/// strength-pivot P5.3 — "Do this workout" on the Coach card materializes the top
/// prescription into a logger session pre-filled with the prescribed movement,
/// planned sets/reps, and working load.
final class P5DoThisUITests: CadenceUITestCase {

    /// With seeded history the engine prescribes progressing a concrete lift; "Do this
    /// workout" opens a session pre-loaded with that movement, its prescribed reps, and
    /// the prescribed load (surfaced on the planned card and pre-filled in the keypad).
    func testDoThisPreFillsPrescribedLiftAndLoad() {
        // Seeded history → Back Squat is the top-ranked progression (140 kg).
        let app = XCUIApplication.launched(seeds: ["history"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.scrollToHittableAndTap("coach.card.doThis"), "Do this workout")

        // We land in the logger on the prescribed session.
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25),
                      "the prescription opens the logger")

        // The prescribed movement is pre-loaded as a planned card with a load-bearing
        // prescription line ("6-6-6 reps @ 140 kg").
        let planned = app.descendants(matching: .any)["exerciseCard.Back Squat"]
        XCTAssertTrue(planned.waitForExistence(timeout: 5), "prescribed movement pre-loaded")
        let rx = app.descendants(matching: .any)["session.rx.Back Squat"].firstMatch
        XCTAssertTrue(rx.waitForExistence(timeout: 5), "prescription line shown")
        XCTAssertTrue((rx.label).contains("@"), "the prescription line carries the working load")

        // Opening the set keypad for the prescribed movement pre-fills the load.
        app.buttons["set.add.Back Squat"].tap()
        let weight = app.staticTexts["set.weight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 10), "weight keypad")
        let entry = (weight.value as? String) ?? ""
        XCTAssertFalse(entry.isEmpty, "the keypad weight is pre-filled with the prescribed load")
        XCTAssertNotEqual(entry, "0", "the prescribed load is non-zero")
    }

    /// Cold start (no history) still offers "Do this workout"; the engine's starter
    /// prescription opens an empty full-body session to log into.
    func testDoThisColdStartOpensSession() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.scrollToHittableAndTap("coach.card.doThis"), "Do this workout")
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25),
                      "the starter prescription opens the logger")
    }
}
