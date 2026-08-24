import XCTest

/// Shared launch + interaction helpers for Cadence UI tests. The app runs in
/// `-uiTest` mode (in-memory store, deterministic fake Health/BLE/GPS) so tests
/// are stable on the simulator, which has no real sensor data.
extension XCUIApplication {
    @discardableResult
    static func launched(seeds: [String] = [], extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTest"]
        for s in seeds { app.launchArguments += ["-seed", s] }
        app.launchArguments += extraArgs
        app.launch()
        return app
    }

    /// Legacy tab labels → the Home launchpad card that now reaches the same
    /// destination (field-testing §01 removed the tab bar). The Trends and Cardio
    /// screens were removed in feedback batch 3, so only Train/Settings remain.
    private static let homeCard = [
        "Today": "home.today", "Train": "home.train", "Settings": "home.settings"
    ]

    /// Swipes up until a button with `id` is present (lazy Form sections aren't
    /// in the accessibility tree until scrolled into view), then taps it.
    @discardableResult
    func scrollToAndTapButton(_ id: String, maxSwipes: Int = 6) -> Bool {
        let button = buttons[id]
        if button.waitForExistence(timeout: 2) { button.tap(); return true }
        for _ in 0..<maxSwipes {
            swipeUp()
            if button.waitForExistence(timeout: 1) { button.tap(); return true }
        }
        return false
    }

    /// Scrolls a (scrollable) screen until `id` is on-screen and HITTABLE, then
    /// taps it. Off-screen elements in a ScrollView "exist" but aren't hittable,
    /// so existence alone isn't enough on the Home dashboard.
    @discardableResult
    func scrollToHittableAndTap(_ id: String, maxSwipes: Int = 8) -> Bool {
        if id == "tab.plan" {
            let tab = tabBars.buttons["Plan"]
            if tab.waitForExistence(timeout: 6) { tab.tap(); return true }
        }
        let button = buttons[id]
        let el = button.exists ? button : descendants(matching: .any)[id]
        guard el.waitForExistence(timeout: 6) else { return false }
        if el.isHittable { el.tap(); return true }
        // Swipe both ways. An element parked under the top scroll-edge glass band
        // is not hittable there, and swiping up only pushes it further under —
        // which is exactly how a returning-from-a-sheet scroll offset used to make
        // Home's Start Workout permanently untappable (2026-08-23).
        for _ in 0..<maxSwipes {
            swipeUp()
            if el.isHittable { el.tap(); return true }
        }
        for _ in 0..<maxSwipes {
            swipeDown()
            if el.isHittable { el.tap(); return true }
        }
        // Fall back to a direct tap (XCUITest will attempt to scroll into view).
        el.tap()
        return true
    }

    /// Scrolls a (scrollable) screen until `id` exists in the accessibility tree
    /// (lazy grids don't materialize off-screen cells). Returns whether it was
    /// found. Does NOT tap — for assertions that only need existence/frame.
    @discardableResult
    func scrollToElement(_ id: String, maxSwipes: Int = 8) -> Bool {
        let el = descendants(matching: .any)[id]
        if el.waitForExistence(timeout: 3) { return true }
        for _ in 0..<maxSwipes {
            swipeUp()
            if el.waitForExistence(timeout: 1) { return true }
        }
        return false
    }

    /// Taps `sourceID` and waits until it reveals `destID`, re-tapping if the tap
    /// is dropped on a slow/degraded simulator (the element is tapped but the
    /// resulting sheet/overlay never opens). Re-taps only while the source is
    /// still hittable, so it never taps *through* the surface it just opened —
    /// once the destination is presenting, the source is covered and we simply
    /// wait. `destID` is matched as either a generic descendant (sheets, overlays,
    /// buttons) OR a navigation bar title, since a pushed NavigationStack
    /// destination surfaces its title on the nav bar (not as a plain descendant
    /// identifier). Returns whether `destID` appeared.
    @discardableResult
    func tapToReveal(_ sourceID: String, _ destID: String,
                     attempts: Int = 2, perAttempt: TimeInterval = 5) -> Bool {
        let source = buttons[sourceID]
        let dest = descendants(matching: .any)[destID]
        let navDest = navigationBars[destID]
        func revealed() -> Bool { dest.exists || navDest.exists }
        guard source.waitForExistence(timeout: 15) else { return false }
        for _ in 0..<attempts {
            if revealed() { return true }
            if source.isHittable { source.tap() }
            let deadline = Date().addingTimeInterval(perAttempt)
            while Date() < deadline {
                if revealed() { return true }
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        return revealed()
    }

    /// Navigates from anywhere back to the Home launchpad, then into the
    /// destination that used to be a tab (field-testing §01).
    func goToTab(_ label: String) {
        popToHome()
        switch label {
        case "Today":
            return  // activity (step count + weekly tiles) lives on Home now
        default:
            // The Home dashboard scrolls, so the "See all" link may be below the
            // fold — scroll until it's hittable before tapping. (Trends/Cardio
            // screens were removed in feedback batch 3.)
            let map = ["Train": "home.train", "Settings": "home.settings"]
            guard let id = map[label] else { XCTFail("unknown destination \(label)"); return }
            XCTAssertTrue(scrollToHittableAndTap(id), "home destination \(label) (\(id)) not found")
        }
    }

    /// Starts a blank strength session the way the app now does it: Home → Start
    /// Workout → Quick Start. Quick Start goes directly into the active session
    /// (or its warm-up), without opening the plan/settings editor.
    @discardableResult
    func startQuickStartStrength() -> Bool {
        popToHome()
        guard scrollToHittableAndTap("home.startWorkout") else { return false }
        guard scrollToHittableAndTap("selectWorkout.quickStart") else { return false }
        return buttons["session.addExercise"].waitForExistence(timeout: 25)
    }

    /// Starts a blank strength session without adding anything in the editor.
    @discardableResult
    func startEmptyStrengthWorkout() -> Bool {
        startQuickStartStrength()
    }

    /// Adds an exercise to the open `WorkoutPlanEditor` and returns after the
    /// editor renders the planned exercise row.
    @discardableResult
    func addExerciseToOpenWorkoutPlan(_ name: String) -> Bool {
        guard scrollToAndTapButton("editor.addExercise", maxSwipes: 8) else { return false }
        guard pickExerciseFromPresentedPicker(name) else { return false }
        return descendants(matching: .any)["editor.exercise.\(name)"].waitForExistence(timeout: 10)
    }

    /// Opens the exercise picker from a live session and picks `name`
    /// deterministically by typing into search — independent of which tab the
    /// picker defaults to (Recents can be empty in a fresh -uiTest store). Picker
    /// rows are NavigationLinks into the exercise detail, so we confirm via the
    /// detail page's Add action when it appears.
    @discardableResult
    func pickExercise(_ name: String) -> Bool {
        guard buttons["session.addExercise"].waitTap() else { return false }
        return pickExerciseFromPresentedPicker(name)
    }

    /// Picks `name` from the currently presented exercise picker.
    @discardableResult
    func pickExerciseFromPresentedPicker(_ name: String) -> Bool {
        let field = searchFields.firstMatch
        guard field.waitForExistence(timeout: 10) else { return false }
        field.tap(); field.typeText(name)
        guard buttons["picker.row.\(name)"].waitTap() else { return false }
        // The row pushes the exercise detail; its Add action plans the exercise
        // back on the session and dismisses the picker.
        if buttons["detail.add"].waitForExistence(timeout: 10) {
            buttons["detail.add"].tap()
        }
        return true
    }

    /// Adds a seeded training partner to the live session through the partner
    /// bar's + button. The seeded person appears either as a "Recent" shortcut or
    /// as a row in the full list, depending on whether they have trained before.
    @discardableResult
    func addSessionPartner(_ name: String) -> Bool {
        guard buttons["partner.add"].waitTap(timeout: 10) else { return false }
        let quickAdd = buttons["partner.quick.add.\(name)"]
        let listRow = buttons["partner.quick.row.\(name)"]
        if quickAdd.waitForExistence(timeout: 5) {
            quickAdd.tap()
        } else if listRow.waitForExistence(timeout: 5) {
            listRow.tap()
        } else {
            return false
        }
        if buttons["partner.quick.done"].waitForExistence(timeout: 5) {
            buttons["partner.quick.done"].tap()
        }
        // The partner chip in the session's "With:" bar is the confirmation that
        // the roster actually took the partner.
        return descendants(matching: .any)["set.performer.\(name)"].waitForExistence(timeout: 10)
    }

    /// Saves whatever the inline set editor currently shows. Picking an exercise
    /// in a live session opens the editor automatically, so the default draft is
    /// already a loggable set.
    @discardableResult
    func saveSetInEditor() -> Bool {
        guard buttons["setEditor.save"].waitForExistence(timeout: 15) else { return false }
        buttons["setEditor.save"].tap()
        return !buttons["setEditor.save"].waitForExistence(timeout: 5)
    }

    /// Logs one set for `partner` on an exercise already in the session: Add Set →
    /// "Who did this set?" → the partner → Save. The performer rows are keyed by
    /// the person's UUID, which the test cannot know, so the partner is resolved
    /// by name inside the picker sheet.
    @discardableResult
    func logPartnerSet(exercise: String, partner: String) -> Bool {
        // `Add set` lives inside the expanded exercise card, and logging a set
        // collapses it, so re-expand before looking for the button.
        if !buttons["set.add.\(exercise)"].exists {
            let collapsed = buttons.matching(identifier: "exercise.collapsed").firstMatch
            if collapsed.waitForExistence(timeout: 10) { collapsed.tap() }
        }
        guard scrollToHittableAndTap("set.add.\(exercise)") else { return false }
        guard buttons["setEditor.performer"].waitTap(timeout: 15) else { return false }
        let row = buttons.matching(identifier: partner).firstMatch
        let labelled = buttons.containing(NSPredicate(format: "label == %@", partner)).firstMatch
        if row.waitForExistence(timeout: 5) { row.tap() }
        else if labelled.waitForExistence(timeout: 5) { labelled.tap() }
        else { return false }
        return saveSetInEditor()
    }

    /// Resolves a `.confirmationDialog`/alert button by identifier via `firstMatch`.
    /// On iOS 26 the accessibility tree surfaces confirmation-dialog buttons TWICE
    /// (same identifier + frame), so `buttons[id]` throws "Multiple matching
    /// elements". `firstMatch` is stable and hittable, so route dialog taps here.
    func dialogButton(_ id: String) -> XCUIElement {
        buttons.matching(identifier: id).firstMatch
    }

    /// Skips the auto-started rest-timer bar and confirms it's gone. The bar sits
    /// at the bottom of the session, overlapping the End/Pause control bar, so a
    /// stray running rest timer (or its "Skip rest?" confirm dialog) makes
    /// `workout.end` un-hittable. Tapping `rest.skip` opens a confirmation dialog
    /// ("Skip rest?" → destructive "Skip"); dismiss both so the control bar clears.
    func dismissRestBar(attempts: Int = 4) {
        let skip = buttons["rest.skip"]
        guard skip.waitForExistence(timeout: 5) else { return }
        for _ in 0..<attempts {
            guard skip.exists else { return }
            if skip.isHittable { skip.tap() }
            // Tapping Skip opens a "Skip rest?" confirm dialog; confirm it.
            let confirm = confirmSkipRestButton
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
            if !skip.waitForExistence(timeout: 2) { return }
        }
    }

    /// Skips the get-ready countdown (and its "Skip countdown?" confirm) so a
    /// workout start never waits on the 10 s timer in the smoke flow. No-op when
    /// no countdown is showing. The confirm dialog's destructive "Skip" has no
    /// id, so it is resolved by label inside the presented sheet — the
    /// countdown's own Skip button shares the label and would otherwise match
    /// first.
    func skipCountdown() {
        let skip = buttons["countdown.skip"]
        guard skip.waitForExistence(timeout: 3) else { return }
        if skip.isHittable { skip.tap() }
        let confirm = sheets.buttons.matching(identifier: "Skip").firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        XCTAssertFalse(buttons["countdown.cancel"].waitForExistence(timeout: 2),
                       "get-ready countdown did not dismiss after Skip")
    }

    /// Reads the `-uiTestWatchStop` counter surfaced by the app (each call to
    /// `stopWatchWorkout()` in that mode increments `uitest.watchStopCount`).
    /// Returns -1 if the seam element is missing, which must fail any caller.
    func watchStopCount() -> Int {
        let el = descendants(matching: .any)["uitest.watchStopCount"]
        guard el.waitForExistence(timeout: 5) else { return -1 }
        // Let the @AppStorage-driven hidden text flush before reading its label.
        Thread.sleep(forTimeInterval: 0.4)
        return Int(el.label) ?? -1
    }

    /// The destructive "Skip" button inside the rest-timer "Skip rest?" confirm
    /// dialog. It carries no accessibility id (it's a plain dialog button), so
    /// resolve it by label via `firstMatch` (iOS 26 duplicates dialog buttons in
    /// the a11y tree), preferring the presented sheet/dialog scope.
    private var confirmSkipRestButton: XCUIElement {
        let inSheet = sheets.buttons.matching(identifier: "Skip").firstMatch
        return inSheet.exists ? inSheet : buttons.matching(identifier: "Skip").firstMatch
    }

    /// Enters a weight on the custom numeric keypad popup (feedback batch 6 item 2,
    /// Enters a weight into the inline weight text field and logs the set via
    /// the columnar checkmark button (redesign A3).
    func recordKeypadSet(_ value: String, clear: Bool = false) {
        keypadEnter(value, clear: clear)
        buttons["set.save"].tap()
    }

    /// Types a weight into the inline weight TextField. The columnar redesign
    /// replaced the dedicated weight keypad sheet with an inline text field.
    func keypadEnter(_ value: String, clear: Bool = false) {
        // Inline text field may need focus first — tap it
        let field = textFields["set.weightField"]
        if field.exists { field.tap() }
        XCTAssertTrue(field.waitForExistence(timeout: 25), "inline weight field")
        if clear { field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10)) }
        field.typeText(value)
    }

    /// Taps Back until the Home launchpad (its Start Workout button) is shown.
    func popToHome() {
        // Home and Plan are sibling tabs in the current launchpad layout; a
        // navigation-bar Back tap cannot leave the Plan tab.
        let homeTab = tabBars.buttons["Home"]
        if homeTab.exists && homeTab.isHittable { homeTab.tap() }
        let homeMarker = buttons["home.startWorkout"]
        var guardCount = 0
        while !homeMarker.exists && guardCount < 8 {
            let back = navigationBars.buttons.element(boundBy: 0)
            if back.exists && back.isHittable { back.tap() } else { break }
            guardCount += 1
        }
        _ = homeMarker.waitForExistence(timeout: 5)
    }
}

extension XCUIElement {
    @discardableResult
    func waitTap(timeout: TimeInterval = 5) -> Bool {
        guard waitForExistence(timeout: timeout) else { return false }
        tap()
        return true
    }

    /// Clears and types into a text field. Taps the right edge first so the
    /// caret lands after the (often right-aligned) text and backspaces clear it.
    func clearAndType(_ text: String) {
        coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let current = (value as? String) ?? ""
        if !current.isEmpty && current != (placeholderValue ?? "") {
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2)
            typeText(deletes)
        }
        typeText(text)
    }
}

@MainActor
class CadenceUITestCase: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // Keep every test in a known portrait orientation so one test can't
        // leave the simulator rotated and break the next. `XCTestCase.setUpWithError`
        // is nonisolated, so the override must stay nonisolated even though the
        // class is @MainActor — hop explicitly (UI tests run on the main thread).
        MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = .portrait
        }
    }
}
