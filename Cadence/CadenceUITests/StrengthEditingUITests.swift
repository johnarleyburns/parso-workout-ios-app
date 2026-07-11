import XCTest

/// UI coverage for the strength logging / history-edit / coach-UI bug batch:
/// opt-in partners (1a), removing a partner mid-workout (1b), changing a set's
/// performer while editing (1c), and from history editing the performer (2a),
/// the exercise (2b), the weight (2c) and reps (2d); plus Home's simplified
/// Coach links.
final class StrengthEditingUITests: CadenceUITestCase {

    // MARK: Helpers

    /// Resolves an element by identifier regardless of its XCUI type (a `.plain`
    /// Button wrapping a Text can surface as a static text), then taps it.
    @discardableResult
    private func tapAny(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 20) -> Bool {
        let btn = app.buttons[id]
        if btn.waitForExistence(timeout: timeout) { btn.tap(); return true }
        let any = app.descendants(matching: .any)[id].firstMatch
        guard any.waitForExistence(timeout: 3) else { return false }
        any.tap()
        return true
    }

    private func exists(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 10) -> Bool {
        app.descendants(matching: .any)[id].firstMatch.waitForExistence(timeout: timeout)
    }

    /// Count of performer chips with a given name. The partner bar shows one chip
    /// per roster member, and each attributed set shows another — so counts (not
    /// mere existence) distinguish "in the roster" from "on a set".
    private func performerCount(_ app: XCUIApplication, _ name: String) -> Int {
        app.staticTexts.matching(identifier: "set.performer.\(name)").count
    }

    /// addExercise → pick → type a weight into the inline editor → save, and
    /// confirm a logged row appears.
    private func logSet(_ app: XCUIApplication, exercise: String = "Bench Press", weight: String) {
        XCTAssertTrue(app.pickExercise(exercise), "pick \(exercise)")
        let field = app.textFields["inline.weight"]
        XCTAssertTrue(field.waitForExistence(timeout: 25), "inline weight field")
        field.tap()
        field.typeText(weight)
        XCTAssertTrue(app.buttons["inline.save"].waitTap(), "save set")
        XCTAssertTrue(exists(app, "set.editWeight.\(exercise).1", timeout: 25), "logged set row")
    }

    private func addPartnerViaManage(_ app: XCUIApplication, named name: String) {
        XCTAssertTrue(app.buttons["partner.manage"].waitTap(), "open manage partners")
        let nameField = app.textFields["partner.manage.nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "manage name field")
        nameField.tap()
        nameField.typeText(name)
        XCTAssertTrue(app.buttons["partner.manage.add"].waitTap(), "add partner")
        XCTAssertTrue(app.buttons["partner.manage.done"].waitTap(), "done manage")
    }

    private func openPastSessionForEdit(_ app: XCUIApplication) {
        app.popToHome()
        app.goToTab("Train")
        let row = app.buttons["session.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "history session row")
        row.tap()
        XCTAssertTrue(app.buttons["summary.edit"].waitTap(), "summary edit button")
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 15), "edit screen")
    }

    private func scrollUntilExists(_ app: XCUIApplication, _ el: XCUIElement, maxSwipes: Int = 8) {
        var tries = 0
        while !el.exists && tries < maxSwipes { app.swipeUp(); tries += 1 }
    }

    // MARK: 1a — opt-in partners (unselected partner does not appear)

    func testNoPartnerSelectedStaysSolo() {
        let app = XCUIApplication.launched(seeds: ["person.Sam"])
        app.popToHome()
        XCTAssertTrue(app.scrollToHittableAndTap("home.startWorkout"), "start workout")
        XCTAssertTrue(app.buttons["weights.quickStart"].waitTap(), "quick start")
        // Sam is offered in the editor but left UNCHECKED (partners are opt-in).
        XCTAssertTrue(exists(app, "editor.partner.Sam"), "Sam should be listed in the editor")
        XCTAssertTrue(app.buttons["editor.start"].waitTap(), "start session")
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25), "session screen")

        // Sam was not selected → not in the session roster → no Sam chip anywhere.
        XCTAssertEqual(performerCount(app, "Sam"), 0,
                       "an unselected partner must NOT appear in the workout")
    }

    // MARK: 1b — remove a partner mid-workout (and it stays removed)

    func testRemovePartnerMidWorkout() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")
        addPartnerViaManage(app, named: "Sam")
        // Added partner is scoped → shows in the partner bar.
        XCTAssertTrue(performerCount(app, "Sam") >= 1, "Sam should be in the session after adding")

        // Remove Sam via the discoverable manage sheet.
        XCTAssertTrue(app.buttons["partner.manage"].waitTap(), "open manage")
        XCTAssertTrue(app.buttons["partner.manage.row.Sam"].waitTap(), "uncheck Sam")
        XCTAssertTrue(app.buttons["partner.manage.done"].waitTap(), "done")

        // Removal sticks → Sam is gone (the old bug re-showed everyone).
        let sam = app.staticTexts["set.performer.Sam"].firstMatch
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sam)
        waitForExpectations(timeout: 10)
    }

    // MARK: 1c — change the performer while editing an existing set

    func testChangePerformerWhileEditingSet() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")
        addPartnerViaManage(app, named: "Sam")

        logSet(app, weight: "60")
        // First set rotates to the owner (Me): bar + row both show a Me chip.
        let meBefore = performerCount(app, "Me")
        XCTAssertGreaterThanOrEqual(meBefore, 2, "owner set + bar both tagged Me")

        XCTAssertTrue(tapAny(app, "set.editWeight.Bench Press.1"), "open inline editor")
        XCTAssertTrue(app.buttons["inline.performer"].waitTap(), "performer menu")
        XCTAssertTrue(app.buttons["Sam"].firstMatch.waitTap(), "pick Sam")
        XCTAssertTrue(app.buttons["inline.save"].waitTap(), "save")

        // The set row's chip flips Me → Sam: one fewer Me, an extra Sam.
        let pred = NSPredicate { _, _ in self.performerCount(app, "Me") < meBefore }
        expectation(for: pred, evaluatedWith: NSObject())
        waitForExpectations(timeout: 10)
        XCTAssertGreaterThanOrEqual(performerCount(app, "Sam"), 2, "edited set now attributed to Sam")
    }

    // MARK: 2a — change a past set's performer from history

    func testChangePartnerFromHistory() {
        let app = XCUIApplication.launched(seeds: ["historyPartnerSession"])
        openPastSessionForEdit(app)
        // Bar (scoped Sam) + the one Sam set → two Sam chips.
        XCTAssertTrue(performerCount(app, "Sam") >= 2, "seeded Sam set + roster chip")

        // Sam's set is working set #3; correct it back to Me.
        XCTAssertTrue(tapAny(app, "set.editWeight.Bench Press.3"), "open Sam's set")
        XCTAssertTrue(app.buttons["inline.performer"].waitTap(), "performer menu")
        XCTAssertTrue(app.buttons["Me"].firstMatch.waitTap(), "pick Me")
        XCTAssertTrue(app.buttons["inline.save"].waitTap(), "save")

        // The Sam set becomes a Me set → only the roster Sam chip remains.
        let pred = NSPredicate { _, _ in self.performerCount(app, "Sam") <= 1 }
        expectation(for: pred, evaluatedWith: NSObject())
        waitForExpectations(timeout: 10)
    }

    // MARK: 2b — change which exercise an entry is, from history

    func testChangeExerciseFromHistory() {
        let app = XCUIApplication.launched(seeds: ["priorBench"])
        openPastSessionForEdit(app)
        XCTAssertTrue(exists(app, "exerciseCard.Bench Press", timeout: 15), "bench card")

        XCTAssertTrue(app.buttons["exercise.menu.Bench Press"].waitTap(), "exercise menu")
        XCTAssertTrue(tapAny(app, "exercise.changeExercise.Bench Press"), "change exercise")

        // The exercise picker sheet opens (its container carries "picker.search").
        XCTAssertTrue(exists(app, "picker.search", timeout: 15), "picker opened")
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Overhead Press")
        }
        XCTAssertTrue(tapAny(app, "picker.row.Overhead Press"), "pick Overhead Press")

        XCTAssertTrue(exists(app, "exerciseCard.Overhead Press", timeout: 15),
                      "card should now be Overhead Press")
        XCTAssertFalse(exists(app, "exerciseCard.Bench Press", timeout: 2), "old Bench card gone")
    }

    // MARK: 2c — change weight from history

    func testChangeWeightFromHistory() {
        let app = XCUIApplication.launched(seeds: ["priorBench"])
        openPastSessionForEdit(app)
        XCTAssertTrue(tapAny(app, "set.editWeight.Bench Press.1"), "open weight editor")
        let field = app.textFields["inline.weight"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "inline weight field")
        field.clearAndType("137")
        XCTAssertTrue(app.buttons["inline.save"].waitTap(), "save")

        let updated = app.descendants(matching: .any)["set.editWeight.Bench Press.1"].firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 15), "set row")
        expectation(for: NSPredicate(format: "label CONTAINS %@", "137"), evaluatedWith: updated)
        waitForExpectations(timeout: 10)
    }

    // MARK: 2d — change reps from history

    func testChangeRepsFromHistory() {
        let app = XCUIApplication.launched(seeds: ["priorBench"])
        openPastSessionForEdit(app)
        XCTAssertTrue(tapAny(app, "set.editReps.Bench Press.1"), "open reps editor")
        let field = app.textFields["inline.reps"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "inline reps field")
        field.clearAndType("12")
        XCTAssertTrue(app.buttons["inline.save"].waitTap(), "save")

        let updated = app.descendants(matching: .any)["set.editReps.Bench Press.1"].firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 15), "set row")
        expectation(for: NSPredicate(format: "label CONTAINS %@", "12"), evaluatedWith: updated)
        waitForExpectations(timeout: 10)
    }

    // MARK: 3 — Home Coach links are streamlined

    func testHomeCoachCardUsesPreferencesAndInsightsOnly() {
        let app = XCUIApplication.launched(seeds: ["coachWhyMixedHistory"])
        app.popToHome()
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 15))

        XCTAssertTrue(app.buttons["coach.card.preferences"].exists)
        XCTAssertTrue(app.buttons["coach.card.insights"].exists)
        XCTAssertFalse(app.buttons["coach.card.whyToday"].exists)
        XCTAssertFalse(app.buttons["coach.card.yourWeek"].exists)
    }
}
