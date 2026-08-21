import XCTest
import CadenceCore
@testable import CadenceFeatures

/// Field-test batch 2026-08-20 issue 7: the zone-color mapping the cardio live
/// screens use must match the Apple Watch's scheme, and the `LiveHRBigView`
/// subtitle/bpm copy is asserted headlessly rather than in the simulator (the
/// smoke flow has no live HR source).
final class HRZoneTintTests: XCTestCase {

    // MARK: - HRZoneTint

    func testTintMappingMatchesWatchScheme() {
        XCTAssertEqual(HRZoneTint.tint(for: 1), .zone1) // Z1 cyan
        XCTAssertEqual(HRZoneTint.tint(for: 2), .zone2) // Z2 green
        XCTAssertEqual(HRZoneTint.tint(for: 3), .zone3) // Z3 yellow
        XCTAssertEqual(HRZoneTint.tint(for: 4), .zone4) // Z4 orange
        XCTAssertEqual(HRZoneTint.tint(for: 5), .zone5) // Z5 red
    }

    func testTintOutOfRangeIsNeutral() {
        XCTAssertEqual(HRZoneTint.tint(for: 0), .neutral)
        XCTAssertEqual(HRZoneTint.tint(for: 6), .neutral)
        XCTAssertEqual(HRZoneTint.tint(for: -1), .neutral)
    }

    // MARK: - LiveHRPresenter

    func testSubtitleZones() {
        XCTAssertEqual(LiveHRPresenter.subtitle(zone: 3, avgHR: nil), "Z3 · Aerobic")
        XCTAssertEqual(LiveHRPresenter.subtitle(zone: 5, avgHR: nil), "Z5 · Max")
        XCTAssertEqual(LiveHRPresenter.subtitle(zone: 1, avgHR: nil), "Z1 · Recovery")
        XCTAssertEqual(LiveHRPresenter.subtitle(zone: 2, avgHR: nil), "Z2 · Easy")
        XCTAssertEqual(LiveHRPresenter.subtitle(zone: 4, avgHR: nil), "Z4 · Threshold")
    }

    func testSubtitleAverageSuffix() {
        XCTAssertEqual(LiveHRPresenter.subtitle(zone: 3, avgHR: 138.4), "Z3 · Aerobic · Avg 138 bpm")
        XCTAssertEqual(LiveHRPresenter.subtitle(zone: 5, avgHR: 190.6), "Z5 · Max · Avg 191 bpm")
    }

    func testSubtitleNilAverageOmitsSuffix() {
        XCTAssertEqual(LiveHRPresenter.subtitle(zone: 3, avgHR: nil), "Z3 · Aerobic")
        XCTAssertEqual(LiveHRPresenter.subtitle(zone: 3, avgHR: 0), "Z3 · Aerobic · Avg 0 bpm")
    }

    func testZoneLineAndAvgSuffixComposeTheSubtitle() {
        let zone = 4
        let avg: Double? = 160.2
        XCTAssertEqual(LiveHRPresenter.zoneLine(zone: zone) + LiveHRPresenter.avgSuffix(avgHR: avg),
                       LiveHRPresenter.subtitle(zone: zone, avgHR: avg))
        XCTAssertEqual(LiveHRPresenter.avgSuffix(avgHR: nil), "")
    }

    func testBpmText() {
        XCTAssertEqual(LiveHRPresenter.bpmText(143.2), "143")
        XCTAssertEqual(LiveHRPresenter.bpmText(nil), "—")
        XCTAssertEqual(LiveHRPresenter.bpmText(0), "0")
    }
}
