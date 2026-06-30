import XCTest

/// Generates the App Store screenshot set from deterministic UI-test data.
/// Run manually with CLADIRON_SCREENSHOT_DIR pointing at the desired output folder.
final class AppStoreScreenshotsUITests: CadenceUITestCase {
    private var outputDirectory: URL {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["CLADIRON_SCREENSHOT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("cladiron-app-store-screenshots", isDirectory: true)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    func testCaptureAppStoreScreenshots() throws {
        try resetOutputDirectory()

        let coachApp = launchSeededApp(["coachWhyMixedHistory", "historyMixed", "priorBench"])
        try capture("01-home-coach", app: coachApp)

        XCTAssertTrue(coachApp.buttons["coach.card.insights"].waitTap(timeout: 10),
                      "open Coach insights")
        XCTAssertTrue(coachApp.descendants(matching: .any)["coach.insights.list"].waitForExistence(timeout: 10),
                      "Coach insights screen")
        try capture("02-coach-insights", app: coachApp)

        let firstWhy = coachApp.buttons["coach.card.why"].firstMatch
        if firstWhy.waitForExistence(timeout: 5) {
            firstWhy.tap()
            try capture("03-coach-insight-expanded", app: coachApp)

            let firstCitation = coachApp.buttons["coach.card.citation"].firstMatch
            if firstCitation.waitForExistence(timeout: 5) {
                firstCitation.tap()
                XCTAssertTrue(coachApp.descendants(matching: .any)["citation.detail"].waitForExistence(timeout: 10),
                              "citation detail")
                try capture("04-citation-detail", app: coachApp)
            }
        }

        let strengthApp = launchSeededApp(["priorBench"])
        XCTAssertTrue(strengthApp.startEmptyStrengthWorkout(), "strength session screen")
        strengthApp.buttons["session.addExercise"].tap()
        XCTAssertTrue(strengthApp.buttons["picker.row.Bench Press"].waitTap(), "pick Bench Press")
        _ = strengthApp.textFields["inline.weight"].waitForExistence(timeout: 10)
        try capture("05-strength-logging", app: strengthApp)

        let progressApp = launchSeededApp(["historyMixed", "priorBench"])
        XCTAssertTrue(progressApp.tabBars.buttons["Progress"].waitTap(timeout: 10), "open Progress")
        XCTAssertTrue(progressApp.descendants(matching: .any)["progress"].waitForExistence(timeout: 10),
                      "Progress screen")
        try capture("06-progress", app: progressApp)

        let planningApp = launchSeededApp(["coachCyclePreference"])
        XCTAssertTrue(planningApp.scrollToHittableAndTap("home.planning"), "open Programs")
        XCTAssertTrue(planningApp.descendants(matching: .any)["planning"].waitForExistence(timeout: 10),
                      "Programs screen")
        try capture("07-programs", app: planningApp)

        let settingsApp = launchSeededApp(["coachCyclePreference"])
        XCTAssertTrue(settingsApp.scrollToHittableAndTap("home.settings"), "open Settings")
        XCTAssertTrue(settingsApp.scrollToHittableAndTap("settings.export"), "open Export")
        XCTAssertTrue(settingsApp.navigationBars["Export"].waitForExistence(timeout: 10),
                      "Export screen")
        _ = settingsApp.descendants(matching: .any)["export.preview"].waitForExistence(timeout: 3)
        try capture("08-backup-export", app: settingsApp)

        settingsApp.popToHome()
        XCTAssertTrue(settingsApp.scrollToHittableAndTap("home.settings"), "open Settings again")
        XCTAssertTrue(settingsApp.scrollToAndTapButton("settings.support", maxSwipes: 10), "open Support")
        XCTAssertTrue(settingsApp.navigationBars["Support Cladiron"].waitForExistence(timeout: 10),
                      "Support screen")
        _ = settingsApp.descendants(matching: .any)["contribution.support"].waitForExistence(timeout: 3)
        try capture("09-support", app: settingsApp)
    }

    private func launchSeededApp(_ seeds: [String]) -> XCUIApplication {
        let app = XCUIApplication.launched(seeds: seeds, extraArgs: ["-todaySteps", "9200"])
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 25),
                      "Home should load for seeds: \(seeds.joined(separator: ", "))")
        return app
    }

    private func resetOutputDirectory() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let pngFiles = try manager.contentsOfDirectory(at: outputDirectory,
                                                       includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "png" }
        for file in pngFiles {
            try manager.removeItem(at: file)
        }
    }

    private func capture(_ name: String, app: XCUIApplication) throws {
        // Let SwiftUI settle before taking the frame that will go to App Store Connect.
        Thread.sleep(forTimeInterval: 0.8)

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let destination = outputDirectory.appendingPathComponent("\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: destination, options: .atomic)
            print("Saved screenshot: \(destination.path)")
        } catch {
            print("Could not write screenshot \(name) to \(destination.path): \(error)")
        }

        XCTAssertTrue(app.exists)
    }
}
