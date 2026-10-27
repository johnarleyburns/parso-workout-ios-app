import XCTest
@testable import CadenceFeatures

final class WatchHRLiveStatusTests: XCTestCase {
    func testRoundTripAndNoBPM() {
        let id = UUID(); let end = Date(timeIntervalSince1970: 1234)
        let s = WatchHRLiveStatus(requestID: id, lastRealSampleEnd: end, sensorHasFreshReading: false)
        XCTAssertNil(s.payload["bpm"])
        XCTAssertEqual(WatchHRLiveStatus(payload: s.payload), s)
    }
    func testMalformedRejected() {
        XCTAssertNil(WatchHRLiveStatus(payload: ["requestID": UUID().uuidString]))
        XCTAssertNil(WatchHRLiveStatus(payload: [WatchHRLiveStatus.key: true, "requestID": "nope"]))
    }
}
