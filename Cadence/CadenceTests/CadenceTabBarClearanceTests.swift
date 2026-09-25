import XCTest
@testable import Cadence

final class CadenceTabBarClearanceTests: XCTestCase {
    func testDockAndContentClearanceLeaveRoomForTheLastRow() {
        let metrics = CadenceDockMetrics()

        XCTAssertGreaterThan(metrics.nominalHeight, metrics.tabHitTarget)
        XCTAssertGreaterThan(CadenceTabBarClearance.extraBottom, 0)
        XCTAssertGreaterThan(CadenceTabBarClearance.scrollContentBottom, 0)
    }
}
