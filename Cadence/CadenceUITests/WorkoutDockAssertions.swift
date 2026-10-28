import XCTest

/// Reusable geometry/hittability checks for the shared `WorkoutControlBar` dock.
/// Contains no test functions (the UI suite is capped at one per device); the
/// single smoke flow calls it for each hosted modality. Ids follow the existing
/// `<prefix>.pause` / `<prefix>.end` scheme from `WorkoutDockPresenter`.
struct WorkoutDockAssertions {
    let app: XCUIApplication
    /// Consumer prefix: workout (strength), record, interval, swim, outdoor.
    var idPrefix: String = "workout"

    /// Minimum rendered height of a primary dock action, in points.
    static let minimumTargetHeight: CGFloat = 56
    /// Allowed width difference between the two primary buttons side by side.
    static let equalWidthTolerance: CGFloat = 1

    func assertPrimaryControls(
        stackedAllowed: Bool = false,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let pause = app.buttons["\(idPrefix).pause"]
        let end = app.buttons["\(idPrefix).end"]
        let who = "[\(idPrefix)]"
        XCTAssertTrue(pause.waitForExistence(timeout: 5), "\(who) pause/resume missing", file: file, line: line)
        XCTAssertTrue(end.exists, "\(who) finish missing", file: file, line: line)
        XCTAssertTrue(pause.isHittable && end.isHittable, "\(who) dock control not hittable", file: file, line: line)
        XCTAssertGreaterThanOrEqual(pause.frame.height, Self.minimumTargetHeight,
                                    "\(who) pause height", file: file, line: line)
        XCTAssertGreaterThanOrEqual(end.frame.height, Self.minimumTargetHeight,
                                    "\(who) finish height", file: file, line: line)
        XCTAssertFalse(pause.frame.intersects(end.frame), "\(who) controls overlap", file: file, line: line)
        if !stackedAllowed {
            XCTAssertEqual(pause.frame.width, end.frame.width, accuracy: Self.equalWidthTolerance,
                           "\(who) primary buttons differ in width", file: file, line: line)
        }
        let bottom = app.windows.firstMatch.frame.maxY
        XCTAssertLessThanOrEqual(end.frame.maxY, bottom, "\(who) finish below screen", file: file, line: line)
    }
}
