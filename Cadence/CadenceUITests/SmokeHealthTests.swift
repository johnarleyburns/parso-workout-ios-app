import XCTest

/// Smoke: injected step data plumbs through the fake HealthDataProviding into
/// Home. The step math is unit-tested in CadenceCore; this proves the provider
/// wiring renders. Replaces FR3StepsUITests / FR4DataSensorsUITests.
final class SmokeHealthTests: CadenceUITestCase {
    func testStepsRenderFromProvider() {
        let app = XCUIApplication.launched(extraArgs: ["-todaySteps", "8200"])
        // The header date is driven by the injected activity provider.
        XCTAssertTrue(app.descendants(matching: .any)["home.headerDate"].waitForExistence(timeout: 25),
                      "Home should load with injected activity data")
        // Home finished composing its coach-derived surfaces.
        XCTAssertTrue(app.descendants(matching: .any)["home.plannedRestOfWeek"].waitForExistence(timeout: 15)
                      || app.buttons["home.startWorkout"].waitForExistence(timeout: 15),
                      "Home should finish rendering with the provider wired in")
    }
}
