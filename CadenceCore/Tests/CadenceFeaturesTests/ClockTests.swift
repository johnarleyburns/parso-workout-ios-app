import XCTest
import CadenceFeatures

final class ClockTests: XCTestCase {
    func testFixedClockReturnsPinnedInstant() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let clock = Clock.fixed(t)
        XCTAssertEqual(clock.now(), t)
        XCTAssertEqual(clock.now(), t)
    }

    func testLiveClockAdvances() {
        let clock = Clock.live
        let a = clock.now()
        XCTAssertGreaterThanOrEqual(clock.now().timeIntervalSince(a), 0)
    }
}
