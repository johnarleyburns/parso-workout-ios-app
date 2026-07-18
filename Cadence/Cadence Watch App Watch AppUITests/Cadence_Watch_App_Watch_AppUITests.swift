import XCTest

final class Cadence_Watch_App_Watch_AppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {}

    @MainActor
    func testBoxingCountdownAdvances() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTest", "-uiTestBoxingInterval"]
        app.launch()

        let countdownLabel = app.staticTexts["intervalCountdown"]
        XCTAssertTrue(countdownLabel.waitForExistence(timeout: 5), "Countdown label not found")

        let before = countdownLabel.label
        let wait = expectation(description: "Countdown advances")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { wait.fulfill() }
        waitForExpectations(timeout: 5)

        let after = countdownLabel.label
        XCTAssertNotEqual(before, after, "Countdown did not advance: \(before) → \(after)")
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
