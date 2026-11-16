import XCTest
import Foundation

/// Structural guard for #740: SwiftUI layout isn't observable from a host
/// XCTest, so this confirms the quick-repeat row is actually wired into
/// `dashboardTopContent` — present, after the start-controls branch, with
/// the accessibility identifier the device checklist and #741's XCUITest
/// extension rely on.
final class TodayQuickRepeatPlacementTests: XCTestCase {
    private var featuresDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Cadence/Cadence/Features/Home")
    }

    func testQuickRepeatRowIsPresentAfterStartControls() throws {
        let file = featuresDir.appendingPathComponent("HomeView+DashboardContent.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let startControlsRange = try XCTUnwrap(source.range(of: "HomeWorkoutStartControls("))
        let presenterRange = try XCTUnwrap(source.range(of: "TodayQuickRepeatPresenter.make("))
        let identifierRange = try XCTUnwrap(source.range(of: "\"home.repeatLastWorkout\""))
        XCTAssertTrue(startControlsRange.upperBound < presenterRange.lowerBound,
                      "the quick-repeat row must come after the start controls")
        XCTAssertTrue(presenterRange.upperBound < identifierRange.lowerBound)
    }
}
