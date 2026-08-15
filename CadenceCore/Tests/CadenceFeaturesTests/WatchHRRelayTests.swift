import XCTest
@testable import CadenceFeatures

@MainActor
final class WatchHRRelayTests: XCTestCase {
    func testSamplesFromAnOlderRequestAreRejected() {
        let relay = WatchHRRelay()
        let oldRequest = UUID()
        let currentRequest = UUID()
        let start = Date(timeIntervalSince1970: 100)
        relay.begin(requestID: currentRequest, now: start)

        XCTAssertFalse(relay.receive(bpm: 140, requestID: oldRequest, now: start.addingTimeInterval(1)))
        XCTAssertNil(relay.freshBPM(at: start.addingTimeInterval(1)))
        XCTAssertTrue(relay.receive(bpm: 141, requestID: currentRequest, now: start.addingTimeInterval(2)))
        XCTAssertEqual(relay.freshBPM(at: start.addingTimeInterval(2)), 141)
    }

    func testLiveHeartRateBecomesStaleAfterTenSeconds() {
        let relay = WatchHRRelay()
        let request = UUID()
        let start = Date(timeIntervalSince1970: 200)
        relay.begin(requestID: request, now: start)
        XCTAssertTrue(relay.receive(bpm: 132, requestID: request, now: start.addingTimeInterval(1)))
        XCTAssertEqual(relay.freshBPM(at: start.addingTimeInterval(11)), 132)
        XCTAssertNil(relay.freshBPM(at: start.addingTimeInterval(11.01)))
    }
}
