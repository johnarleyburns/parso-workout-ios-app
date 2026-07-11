import XCTest

/// P3 (issue 11) — the coach's weekly "run this fitness test" card. A fresh install
/// has no assessments, so the highest-priority never-tested kind should surface.
/// The card exposes Start test / Pick a different test / Not right now.
final class CoachTestRecommendationUITests: CadenceUITestCase {

    func testFreshInstallShowsTestRecommendationCard() {
        let app = XCUIApplication.launched()
        let card = app.otherElements["coach.test.card"]
        XCTAssertTrue(scrollToElement(card, in: app),
                      "A fresh install with no assessments should surface a fitness-test recommendation")
        XCTAssertTrue(app.buttons["coach.test.start"].exists, "Card should offer Start test")
        XCTAssertTrue(app.buttons["coach.test.pickDifferent"].exists, "Card should offer Pick a different test")
        XCTAssertTrue(app.buttons["coach.test.snooze"].exists, "Card should offer Not right now")
    }

    func testPickDifferentTestAdvancesKind() {
        let app = XCUIApplication.launched()
        let card = app.otherElements["coach.test.card"]
        XCTAssertTrue(scrollToElement(card, in: app))
        let title = app.staticTexts["coach.test.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let first = title.label
        app.buttons["coach.test.pickDifferent"].tap()
        // The title should change to a different test kind. Re-query each poll so a
        // recreated SwiftUI element doesn't leave us holding a stale handle.
        var changed = false
        for _ in 0..<20 {
            if app.staticTexts["coach.test.title"].label != first { changed = true; break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(changed, "Pick a different test should advance to another kind")
    }

    func testNotRightNowDismissesCard() {
        let app = XCUIApplication.launched()
        let card = app.otherElements["coach.test.card"]
        XCTAssertTrue(scrollToElement(card, in: app))
        app.buttons["coach.test.snooze"].tap()
        let gone = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: gone, object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [exp], timeout: 5), .completed,
                       "Not right now should dismiss the card")
    }

    // MARK: helpers

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 10) { return true }
        for _ in 0..<8 where !element.exists {
            app.swipeUp()
        }
        return element.exists
    }
}
