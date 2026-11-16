import XCTest
import CadenceFeatures

/// Deliberately no @testable: the Watch app consumes this public initializer.
final class WatchLiftLaunchPublicAPITests: XCTestCase {
    func testWatchAppCanConstructFreshSuggestionLaunch() {
        let launch = WatchLiftLaunch(title: "Suggested", exerciseNames: ["Biceps Curl"], repLadder: [10])
        XCTAssertEqual(launch.title, "Suggested")
        XCTAssertEqual(launch.exerciseNames, ["Biceps Curl"])
        XCTAssertEqual(launch.repLadder, [10])
        XCTAssertNil(launch.planPayload)
    }
}
