import XCTest
@testable import CadenceFeatures

final class WeeklySetProgressTests: XCTestCase {
    func testZonesUseExactFourEightAndTwelveSetBoundaries() {
        XCTAssertEqual(WeeklySetProgress.zone(for: 0), .belowMinimum)
        XCTAssertEqual(WeeklySetProgress.zone(for: 3.5), .belowMinimum)
        XCTAssertEqual(WeeklySetProgress.zone(for: 4), .building)
        XCTAssertEqual(WeeklySetProgress.zone(for: 7.5), .building)
        XCTAssertEqual(WeeklySetProgress.zone(for: 8), .productive)
        XCTAssertEqual(WeeklySetProgress.zone(for: 12), .productive)
        XCTAssertEqual(WeeklySetProgress.zone(for: 12.5), .aboveMaximum)
        XCTAssertEqual(WeeklySetProgress.zone(for: -1), .belowMinimum)
    }

    func testNormalizedSetsClampAtZeroAndTwelve() {
        XCTAssertEqual(WeeklySetProgress.normalized(-1), 0)
        XCTAssertEqual(WeeklySetProgress.normalized(0), 0)
        XCTAssertEqual(WeeklySetProgress.normalized(3.5), 3.5 / 12, accuracy: 0.0001)
        XCTAssertEqual(WeeklySetProgress.normalized(12), 1)
        XCTAssertEqual(WeeklySetProgress.normalized(12.5), 1)
    }

    func testZonesExposeOnlySemanticTintRoles() {
        XCTAssertEqual(WeeklySetZone.belowMinimum.tintRole, .red)
        XCTAssertEqual(WeeklySetZone.building.tintRole, .yellow)
        XCTAssertEqual(WeeklySetZone.productive.tintRole, .green)
        XCTAssertEqual(WeeklySetZone.aboveMaximum.tintRole, .red)
    }
}
