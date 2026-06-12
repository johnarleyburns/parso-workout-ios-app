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
    /// destination (field-testing §01 removed the tab bar). Lets the existing
    /// FR1–FR6 suites navigate unchanged through `goToTab`.
    private static let homeCard = [
        "Today": "home.today", "Train": "home.train", "Cardio": "home.cardio",
        "Trends": "home.stats", "Settings": "home.settings"
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

    /// Navigates from anywhere back to the Home launchpad, then into the
    /// destination that used to be a tab (field-testing §01).
    func goToTab(_ label: String) {
        popToHome()
        switch label {
        case "Today":
            return  // activity (step count + trend) lives on Home now
        case "Cardio":
            // Cardio history reached via the Stats "See all" then the cardio link.
            XCTAssertTrue(scrollToHittableAndTap("home.stats"), "open Stats")
            XCTAssertTrue(scrollToHittableAndTap("stats.cardio"), "stats.cardio not found")
        default:
            // The Home dashboard scrolls, so the "See all" link may be below the
            // fold — scroll until it's hittable before tapping.
            let map = ["Train": "home.train", "Trends": "home.stats", "Settings": "home.settings"]
            guard let id = map[label] else { XCTFail("unknown destination \(label)"); return }
            XCTAssertTrue(scrollToHittableAndTap(id), "home destination \(label) (\(id)) not found")
        }
    }

    /// Starts a blank strength session the way the app now does it: Home → Start
    /// Workout → Weights → Quick Start. (The New Workout button was removed from
    /// History — round4b feedback #1/#4.) Lands on the session screen. In UI-test
    /// mode the get-ready countdown defaults to 0, so this goes straight through.
    @discardableResult
    func startEmptyStrengthWorkout() -> Bool {
        popToHome()
        guard scrollToHittableAndTap("home.startWorkout") else { return false }
        guard buttons["startType.weights"].waitTap() else { return false }
        guard buttons["weights.quickStart"].waitTap() else { return false }
        return buttons["session.addExercise"].waitForExistence(timeout: 25)
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
    func waitTap(timeout: TimeInterval = 25) -> Bool {
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
