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
        let el = buttons[id]
        guard el.waitForExistence(timeout: 6) else { return false }
        if el.isHittable { el.tap(); return true }
        for _ in 0..<maxSwipes {
            swipeUp()
            if el.isHittable { el.tap(); return true }
        }
        // Fall back to a direct tap (XCUITest will attempt to scroll into view).
        el.tap()
        return true
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
    /// Workout → Weights → Quick Start. Lands on the editor first, so callers can
    /// optionally plan exercises before tapping Start.
    @discardableResult
    func openQuickStartStrengthEditor() -> Bool {
        popToHome()
        guard scrollToHittableAndTap("home.startWorkout") else { return false }
        guard buttons["weights.quickStart"].waitTap() else { return false }
        return buttons["editor.start"].waitForExistence(timeout: 10)
    }

    /// Starts a blank strength session without adding anything in the editor.
    @discardableResult
    func startEmptyStrengthWorkout() -> Bool {
        guard openQuickStartStrengthEditor() else { return false }
        guard buttons["editor.start"].waitTap() else { return false }
        return buttons["session.addExercise"].waitForExistence(timeout: 25)
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

class CadenceUITestCase: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // Keep every test in a known portrait orientation so one test can't
        // leave the simulator rotated and break the next.
        XCUIDevice.shared.orientation = .portrait
    }
}
