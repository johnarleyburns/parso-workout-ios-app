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

    func testAlreadyActiveShouldRetryAfterStop() {
        XCTAssertTrue(WatchHRRelay.shouldRetryAfterStop(rejection: .alreadyActive))
    }

    func testNonRetryableRejectionsShouldNotRetry() {
        let nonRetryable: [WatchHRRejection?] = [.healthPermissionDenied, .unsupported,
                                                 .unavailable, .sessionStartFailed, nil]
        for rejection in nonRetryable {
            XCTAssertFalse(WatchHRRelay.shouldRetryAfterStop(rejection: rejection),
                           "rejection \(String(describing: rejection)) must not auto-retry")
        }
    }

    func testRelayRecoverySequence() {
        // The stop-then-retry path: first request fails "already active", the
        // phone tears the stale session down and begins a fresh request which
        // the watch acknowledges and feeds samples to.
        let relay = WatchHRRelay()
        let first = UUID()
        let retry = UUID()
        let start = Date(timeIntervalSince1970: 300)
        relay.begin(requestID: first, now: start)
        relay.fail("Apple Watch rejected heart-rate monitoring (alreadyActive)")
        relay.begin(requestID: retry, now: start.addingTimeInterval(2))
        relay.acknowledged(now: start.addingTimeInterval(3))
        XCTAssertTrue(relay.receive(bpm: 138, requestID: retry, now: start.addingTimeInterval(4)))
        XCTAssertEqual(relay.freshBPM(at: start.addingTimeInterval(5)), 138)
        XCTAssertEqual(relay.activeRequestID, retry)
    }
}
