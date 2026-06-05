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

    /// Tab labels → their SF Symbol, which SwiftUI uses as the tab button's
    /// accessibility identifier (stable on both the iPhone bottom bar and the
    /// iPad top bar, and free of the nav-title label collision).
    private static let tabSymbol = [
        "Today": "sun.max", "Train": "dumbbell", "Cardio": "figure.run",
        "Trends": "chart.xyaxis.line", "Settings": "gear"
    ]

    func goToTab(_ label: String) {
        let byTabBar = tabBars.buttons[label]
        if byTabBar.waitForExistence(timeout: 3) { byTabBar.tap(); return }
        if let symbol = Self.tabSymbol[label] {
            let bySymbol = buttons[symbol].firstMatch
            if bySymbol.waitForExistence(timeout: 3) { bySymbol.tap(); return }
        }
        let byLabel = buttons.matching(identifier: label).firstMatch
        if byLabel.waitForExistence(timeout: 3) { byLabel.tap(); return }
        XCTFail("tab \(label) not found")
    }
}

extension XCUIElement {
    @discardableResult
    func waitTap(timeout: TimeInterval = 10) -> Bool {
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
    }
}
