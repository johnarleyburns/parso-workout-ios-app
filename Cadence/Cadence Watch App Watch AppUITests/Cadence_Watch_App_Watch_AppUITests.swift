import XCTest

final class WatchSmokeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Walks the redesigned flow (plans/watch-redesign/2026-09-30): Settings → About, Quick lift →
    /// custom setup, Plan page → add exercise, Set Card (lifter chip, More, log), Rest, partner
    /// history, Last set, remove exercise, Controls → Discard cancel → Finish → review → Save →
    /// cool-down → receipts. Each mockup state is attached as a screenshot for the fidelity audit.
    @MainActor
    func testWatchStrengthWorkoutStartsLogsAndCompletes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTest", "-ApplePersistenceIgnoreState", "YES", "-seed", "person.Sam"]
        app.launch()

        XCTAssertEqual(app.state, .runningForeground,
                       "Watch app terminated or failed to reach the foreground during cold launch")
        // A fresh simulator clone may show the Heart Rate Access boundary first.
        app.passHealthBoundaryIfShown()
        XCTAssertTrue(app.buttons["watch.startStrength"].waitForExistence(timeout: 15),
                      "Today launcher did not show the Quick lift tile")
        snapshot(app, "T1-today")

        XCTAssertTrue(app.tapButton("watch.settings"), "Today did not expose Settings")
        snapshot(app, "settings")
        XCTAssertTrue(app.tapButton("watch.about", scrollAttempts: 4), "Settings did not expose About")
        XCTAssertTrue(app.staticTexts["Version"].waitForExistence(timeout: 10),
                      "Watch About screen did not show the installed version")
        XCTAssertTrue(app.staticTexts["Build"].waitForExistence(timeout: 5),
                      "Watch About screen did not show the installed build")
        app.terminate()
        app.launch()
        app.passHealthBoundaryIfShown()

        XCTAssertTrue(app.tapButton("watch.startStrength", scrollAttempts: 4),
                      "Today launcher did not show Quick lift")
        XCTAssertTrue(app.tapButton("watchStrength.custom"), "Strength start screen did not show Custom")
        XCTAssertTrue(app.buttons["watchStrength.repPattern.12-10-8"].waitForExistence(timeout: 10),
                      "Custom setup did not show rep-pattern options")
        XCTAssertTrue(app.tapButton("watchStrength.rest.60", scrollAttempts: 3),
                      "Custom setup did not show rest options")
        XCTAssertTrue(app.tapButton("watchStrength.partner.none", scrollAttempts: 4),
                      "Custom setup did not show No partner")
        XCTAssertTrue(app.tapButton("watchStrength.partner.Sam", scrollAttempts: 4),
                      "Custom setup did not show seeded recent partner")
        XCTAssertTrue(app.tapButton("watchStrength.customStart", scrollAttempts: 4),
                      "Custom setup did not start")

        // An empty workout opens on the Plan page.
        XCTAssertTrue(app.tapButton("watchStrength.addExercise", scrollAttempts: 2),
                      "Plan page did not offer Add exercise")
        XCTAssertTrue(app.textFields["watchAddExercise.search"].waitForExistence(timeout: 10),
                      "Watch exercise picker did not expose search first")
        XCTAssertTrue(app.buttons["watchAddExercise.custom"].waitForExistence(timeout: 10),
                      "Watch exercise search did not expose custom exercise creation")
        snapshot(app, "C1-add-exercise")
        XCTAssertTrue(app.tapButton("watchAddExercise.category.chest"),
                      "Watch exercise picker did not show categories")
        XCTAssertTrue(app.tapButtonAfterSmallScroll("watchAddExercise.row.Alternating Floor Press", attempts: 8),
                      "Watch exercise picker did not show a chest exercise")
        XCTAssertTrue(app.tapButton("watchAddExercise.previewAdd"), "Watch exercise preview did not show Add")

        XCTAssertTrue(app.buttons["watchStrength.exercise.Alternating Floor Press"].waitForExistence(timeout: 10),
                      "The added exercise was not on the Plan page")
        snapshot(app, "P3-plan")
        XCTAssertTrue(app.tapButton("watchStrength.exercise.Alternating Floor Press"),
                      "Could not open the exercise from the Plan page")

        // Set Card.
        XCTAssertTrue(app.buttons["logSetButton"].waitForExistence(timeout: 10), "The Set Card did not open")
        snapshot(app, "S1-set-card")
        XCTAssertTrue(app.tapButton("watchStrength.lifterChip"), "The Set Card did not show who is lifting")
        snapshot(app, "C2-partners")
        XCTAssertTrue(app.tapButton("watchPerformer.Sam", scrollAttempts: 3), "Partners did not list Sam")
        XCTAssertTrue(app.tapButton("watchSet.more", scrollAttempts: 2), "The Set Card did not expose More")
        XCTAssertTrue(app.otherElements["watchWeight.platePicker"].waitForExistence(timeout: 10)
                      || app.buttons["watchWeight.platePicker"].exists,
                      "More did not expose the plate step")
        XCTAssertTrue(app.buttons["watchWeight.minusPlate"].waitForExistence(timeout: 10),
                      "More did not expose subtract")
        snapshot(app, "S3-more")
        XCTAssertTrue(app.tapButton("watchWeight.plusPlate", scrollAttempts: 4), "More did not expose add")
        app.closeSheet()

        XCTAssertTrue(app.tapButton("logSetButton", scrollAttempts: 2), "Could not log the set")
        XCTAssertTrue(app.buttons["watchRest.nextSet"].waitForExistence(timeout: 10),
                      "Rest did not appear after logging")
        snapshot(app, "R1-rest")
        XCTAssertTrue(app.tapButton("watchRest.nextSet"), "Rest did not offer Next set")

        // The rotation moved on to the owner, whose history has no sets yet.
        XCTAssertTrue(app.buttons["logSetButton"].waitForExistence(timeout: 10),
                      "Next set did not return to the Set Card")
        XCTAssertTrue(app.tapButton("watchSet.more", scrollAttempts: 2), "More was not available")
        XCTAssertFalse(app.buttons["watchSet.delete.1"].waitForExistence(timeout: 1),
                       "Owner history incorrectly included the partner's set")
        app.closeSheet()
        XCTAssertTrue(app.tapButton("watchStrength.lifterChip"), "Could not open the rotation")
        XCTAssertTrue(app.tapButton("watchPerformer.Sam", scrollAttempts: 3),
                      "Could not switch back to the partner")
        XCTAssertTrue(app.tapButton("watchSet.more", scrollAttempts: 2), "More was not available")
        XCTAssertTrue(app.tapButtonAfterSmallScroll("watchSet.delete.1", attempts: 4),
                      "Partner's own set history was not available")
        XCTAssertTrue(app.tapButtonAfterSmallScroll("lastSetButton", attempts: 6), "More did not offer Log as last set")

        // Back on the Plan page: add a second exercise, then swipe it away.
        XCTAssertTrue(app.tapButton("watchStrength.addExercise", scrollAttempts: 4),
                      "Could not add a second exercise")
        XCTAssertTrue(app.tapButton("watchAddExercise.category.chest"),
                      "Second watch exercise picker did not show categories")
        let secondExerciseRow = app.firstExerciseRow(excluding: "Alternating Floor Press", attempts: 8)
        XCTAssertNotNil(secondExerciseRow, "Watch exercise picker did not show a second chest exercise")
        XCTAssertTrue(app.tapButton("watchAddExercise.previewAdd", scrollAttempts: 4),
                      "Watch exercise preview did not add the second exercise")
        let secondExerciseName = secondExerciseRow?.replacingOccurrences(of: "watchAddExercise.row.", with: "") ?? ""
        XCTAssertTrue(app.buttons["watchStrength.exercise.\(secondExerciseName)"].waitForExistence(timeout: 10),
                      "The second exercise was not on the Plan page")
        XCTAssertTrue(app.tapButton("watchStrength.exercise.\(secondExerciseName)"),
                      "Could not open the second exercise")
        XCTAssertTrue(app.tapButton("watchSet.more", scrollAttempts: 2), "More was not available")
        XCTAssertTrue(app.tapButtonAfterSmallScroll("watchStrength.deleteExercise.\(secondExerciseName)", attempts: 8),
                      "More did not offer Remove exercise")
        XCTAssertTrue(app.tapButton("Remove"),
                      "Remove exercise did not confirm")
        XCTAssertFalse(app.buttons["watchStrength.exercise.\(secondExerciseName)"].waitForExistence(timeout: 3),
                       "The removed exercise was still on the Plan page")

        // Controls page (swipe right from the Set Card / Plan).
        XCTAssertTrue(app.swipeToButton("watchStrength.deleteWorkout", direction: .right, attempts: 3),
                      "The Controls page was not reachable")
        snapshot(app, "P1-controls")
        XCTAssertTrue(app.tapButton("watchStrength.deleteWorkout", scrollAttempts: 2),
                      "Controls did not offer Discard")
        XCTAssertTrue(app.tapButton("Keep Workout"),
                      "Discard confirmation did not offer Keep Workout")
        XCTAssertTrue(app.tapButton("watchStrength.finish", scrollAttempts: 2), "Controls did not offer Finish")
        XCTAssertTrue(app.buttons["watchStrength.save"].waitForExistence(timeout: 10),
                      "Finish did not review before saving")
        snapshot(app, "F1-review")
        XCTAssertTrue(app.tapButton("watchStrength.save"), "Review did not offer Save")

        XCTAssertTrue(app.tapButton("watchCooldown.skip"), "Watch cooldown screen did not appear")
        XCTAssertTrue(app.staticTexts["watchSummary.saved"].waitForExistence(timeout: 10),
                      "Watch summary did not render")
        XCTAssertTrue(app.buttons["watchSummary.done"].waitForExistence(timeout: 10),
                      "Watch summary Done button did not render")
        snapshot(app, "F2-receipts")
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIApplication {
    @MainActor
    func firstExerciseRow(excluding excludedName: String, attempts: Int = 4) -> String? {
        let rows = buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "watchAddExercise.row."))
        for _ in 0...attempts {
            for row in rows.allElementsBoundByIndex {
                guard row.exists, row.isHittable, row.identifier != "watchAddExercise.row.\(excludedName)" else {
                    continue
                }
                let identifier = row.identifier
                row.tap()
                return identifier
            }
            let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            let end = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60))
            start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
        }
        return nil
    }

    @MainActor
    func tapButtonAfterSmallScroll(_ identifier: String, attempts: Int = 4) -> Bool {
        let button = buttons[identifier].firstMatch
        let window = windows.firstMatch.frame
        for _ in 0...attempts {
            // Tap only a row that is fully on screen: a row under the bottom edge reports hittable
            // but its centre is off the display.
            if button.waitForExistence(timeout: 1), button.isHittable, button.frame.maxY <= window.maxY {
                button.tap()
                return true
            }
            // The Crown scrolls whatever list is showing, including one inside the workout pager.
            XCUIDevice.shared.rotateDigitalCrown(delta: 0.25)
        }
        return false
    }

    @MainActor
    func passHealthBoundaryIfShown() {
        let skip = buttons["Continue without heart rate"].firstMatch
        if skip.waitForExistence(timeout: 4) { skip.tap() }
    }

    enum SwipeDirection { case left, right }

    /// Pages the workout pager until a button is on screen.
    @MainActor
    func swipeToButton(_ identifier: String, direction: SwipeDirection, attempts: Int) -> Bool {
        let button = buttons[identifier].firstMatch
        for _ in 0...attempts {
            if button.exists, button.isHittable { return true }
            switch direction {
            case .left: swipeLeft()
            case .right: swipeRight()
            }
            _ = button.waitForExistence(timeout: 1)
        }
        return button.exists
    }

    /// Dismisses a watch sheet (its toolbar close button, else a swipe down).
    @MainActor
    func closeSheet() {
        let close = buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 2) { close.tap() } else { swipeDown() }
    }

    @MainActor
    func tapButton(_ identifier: String, timeout: TimeInterval = 10, scrollAttempts: Int = 0) -> Bool {
        let button = buttons[identifier].firstMatch
        if button.waitForExistence(timeout: timeout) {
            button.tap()
            return true
        }

        for _ in 0..<scrollAttempts {
            swipeUp()
            if button.waitForExistence(timeout: 1) {
                button.tap()
                return true
            }
        }
        return false
    }
}
