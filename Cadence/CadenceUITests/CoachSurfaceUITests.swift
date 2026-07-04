import XCTest

/// End-to-end coverage for the coach presence system (coach-surface-design.md, as
/// amended): introducing card for new free users, the ambient/insight CoachRow once
/// introducing is spent, the pushed CoachPreviewScreen, the always-present Programs
/// entry, and the "Hide Coach offers" opt-out.
final class CoachSurfaceUITests: CadenceUITestCase {

    // MARK: introducing (fresh free user)

    func testFreeIntroducingShowsPreviewCardAtTop() {
        let app = XCUIApplication.launched(extraArgs: ["-proLocked"])
        XCTAssertTrue(app.otherElements["coach.preview"].waitForExistence(timeout: 15),
                      "A fresh free user should see the introducing preview card")
        XCTAssertFalse(app.otherElements["coach.card"].exists,
                       "Free users must not see the full coaching card")
    }

    // MARK: ambient / insight row (introducing spent)

    func testAmbientRowShownAfterIntroImpressionsAndOpensPreviewScreen() {
        let app = XCUIApplication.launched(extraArgs: ["-proLocked", "-coachImpressions", "3"])
        let row = coachRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 15),
                      "After the introducing cap, the compact CoachRow should appear")
        XCTAssertFalse(app.otherElements["coach.preview"].exists,
                       "The full introducing card should be gone in the ambient state")

        row.tap()
        XCTAssertTrue(coachPreviewScreenAppeared(app),
                      "Tapping the CoachRow should push the Coach preview screen with its locked prescription")
    }

    // MARK: hidden

    func testHiddenStateRemovesAllHomeCoachPresence() {
        let app = XCUIApplication.launched(extraArgs: ["-proLocked", "-coachHidden"])
        // Give Home a moment to settle.
        XCTAssertTrue(app.descendants(matching: .any)["home.headerDate"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.otherElements["coach.preview"].exists,
                       "Hidden: no introducing card on Home")
        XCTAssertFalse(coachRow(in: app).exists, "Hidden: no CoachRow on Home")
        XCTAssertFalse(app.otherElements["coach.card"].exists, "Hidden: no coaching card on Home")
    }

    func testHiddenStillReachableFromPrograms() {
        let app = XCUIApplication.launched(extraArgs: ["-proLocked", "-coachHidden"])
        XCTAssertTrue(app.scrollToHittableAndTap("home.planning"), "open Programs")
        let entry = app.buttons["programs.coachEntry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10),
                      "Coach must remain reachable from Programs even when hidden")
        entry.tap()
        XCTAssertTrue(coachPreviewScreenAppeared(app),
                      "Programs coach entry should open the Coach preview screen")
    }

    // MARK: Programs entry (any state)

    func testProgramsHasCoachEntry() {
        let app = XCUIApplication.launched(extraArgs: ["-proLocked"])
        XCTAssertTrue(app.scrollToHittableAndTap("home.planning"), "open Programs")
        XCTAssertTrue(app.buttons["programs.coachEntry"].waitForExistence(timeout: 10),
                      "Programs should always expose a Coach entry row")
    }

    // MARK: Settings hide toggle

    func testSettingsHasHideCoachOffersToggle() {
        let app = XCUIApplication.launched(extraArgs: ["-proLocked"])
        XCTAssertTrue(app.scrollToHittableAndTap("home.settings"), "open Settings")
        let toggle = app.switches["settings.coach.hideOffers"]
        var found = toggle.waitForExistence(timeout: 3)
        for _ in 0..<8 where !found {
            app.swipeUp()
            found = toggle.exists
        }
        XCTAssertTrue(found, "Free users should have a Hide Coach offers toggle in Settings")
    }

    // MARK: helpers

    private func coachRow(in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'coach.row'")
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    /// The pushed preview screen identifier sits on a ScrollView, which doesn't
    /// resolve reliably via `otherElements`; assert on its always-present locked
    /// prescription panel and the "Coach" nav title instead.
    private func coachPreviewScreenAppeared(_ app: XCUIApplication) -> Bool {
        let locked = app.descendants(matching: .any)["coach.previewScreen.lockedPrescription"]
        if locked.waitForExistence(timeout: 10) { return true }
        return app.navigationBars["Coach"].waitForExistence(timeout: 3)
    }
}
