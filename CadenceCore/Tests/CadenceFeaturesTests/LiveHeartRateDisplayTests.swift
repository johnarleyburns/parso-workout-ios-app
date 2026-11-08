import XCTest
import CadenceFeatures

final class LiveHeartRateDisplayTests: XCTestCase {
    func testNoSample() {
        let d = LiveHeartRateDisplay(bpm: nil)
        XCTAssertEqual(d.valueText, "--")
        XCTAssertFalse(d.hasSample)
    }

    func testActiveSample() {
        XCTAssertEqual(LiveHeartRateDisplay(bpm: 118).valueText, "118")
    }

    func testFractionalRounds() {
        XCTAssertEqual(LiveHeartRateDisplay(bpm: 117.5).valueText, "118")
        XCTAssertEqual(LiveHeartRateDisplay(bpm: 117.4).valueText, "117")
    }

    func testNonPositiveOrNonFiniteIsNoSample() {
        XCTAssertFalse(LiveHeartRateDisplay(bpm: 0).hasSample)
        XCTAssertFalse(LiveHeartRateDisplay(bpm: .nan).hasSample)
    }
}
