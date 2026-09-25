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

    func testLiveHeartRateBecomesStaleAfterThreeMissedHeartbeats() {
        let relay = WatchHRRelay()
        let request = UUID()
        let start = Date(timeIntervalSince1970: 200)
        relay.begin(requestID: request, now: start)
        XCTAssertTrue(relay.receive(bpm: 132, requestID: request, now: start.addingTimeInterval(1)))
        XCTAssertEqual(relay.freshBPM(at: start.addingTimeInterval(16)), 132)
        XCTAssertNil(relay.freshBPM(at: start.addingTimeInterval(16.01)))
    }

    func testPhoneLaunchedWatchAppStepsThroughLaunchingConnectingAndLive() {
        let relay = WatchHRRelay()
        let request = UUID()
        let start = Date(timeIntervalSince1970: 400)
        relay.begin(requestID: request, launchingWatchApp: true, now: start)
        XCTAssertEqual(relay.state, .launchingWatchApp(requestID: request, startedAt: start))
        relay.watchAppLaunched(now: start.addingTimeInterval(3))
        XCTAssertEqual(relay.state, .connecting(requestID: request, startedAt: start.addingTimeInterval(3)))
        relay.acknowledged(now: start.addingTimeInterval(4))
        XCTAssertEqual(relay.state, .waitingForSample(requestID: request, acknowledgedAt: start.addingTimeInterval(4)))
        XCTAssertTrue(relay.receive(bpm: 118, requestID: request, now: start.addingTimeInterval(6)))
        XCTAssertEqual(relay.freshBPM(at: start.addingTimeInterval(6)), 118)
    }

    func testWatchReplyCanBeatTheLaunchCallback() {
        let relay = WatchHRRelay()
        let request = UUID()
        let start = Date(timeIntervalSince1970: 500)
        relay.begin(requestID: request, launchingWatchApp: true, now: start)
        relay.acknowledged(now: start.addingTimeInterval(2))
        relay.watchAppLaunched(now: start.addingTimeInterval(3))
        XCTAssertEqual(relay.state, .waitingForSample(requestID: request, acknowledgedAt: start.addingTimeInterval(2)),
                       "a late launch callback must not step back to connecting")
    }

    func testFirstSampleCanArriveWhileStillLaunching() {
        let relay = WatchHRRelay()
        let request = UUID()
        let start = Date(timeIntervalSince1970: 600)
        relay.begin(requestID: request, launchingWatchApp: true, now: start)
        XCTAssertFalse(relay.receive(bpm: 120, requestID: UUID(), now: start.addingTimeInterval(1)))
        XCTAssertTrue(relay.receive(bpm: 120, requestID: request, now: start.addingTimeInterval(1)))
        XCTAssertEqual(relay.freshBPM(at: start.addingTimeInterval(1)), 120)
    }

    func testTimedOutRelayRecoversWhenTheSameWatchSessionResumes() {
        let relay = WatchHRRelay()
        let request = UUID()
        let start = Date(timeIntervalSince1970: 250)
        relay.begin(requestID: request, now: start)
        relay.acknowledged(now: start.addingTimeInterval(1))
        relay.timeout()

        XCTAssertTrue(relay.receive(bpm: 128, requestID: request, now: start.addingTimeInterval(20)))
        XCTAssertEqual(relay.freshBPM(at: start.addingTimeInterval(20)), 128)
        XCTAssertFalse(relay.receive(bpm: 128, requestID: UUID(), now: start.addingTimeInterval(20)))
    }

    func testEveryRejectionHasAPlainMessage() {
        let all: [WatchHRRejection] = [.alreadyActive, .watchWorkoutActive, .unavailable,
                                       .unsupported, .healthPermissionDenied, .sessionStartFailed]
        for rejection in all {
            XCTAssertFalse(rejection.userMessage.isEmpty)
            XCTAssertFalse(rejection.userMessage.contains(rejection.rawValue),
                           "raw rejection codes are not user-facing text")
        }
    }

    func testAlreadyActiveShouldRetryAfterStop() {
        XCTAssertTrue(WatchHRRelay.shouldRetryAfterStop(rejection: .alreadyActive))
    }

    func testNonRetryableRejectionsShouldNotRetry() {
        let nonRetryable: [WatchHRRejection?] = [.healthPermissionDenied, .unsupported,
                                                 .unavailable, .sessionStartFailed,
                                                 .watchWorkoutActive, nil]
        for rejection in nonRetryable {
            XCTAssertFalse(WatchHRRelay.shouldRetryAfterStop(rejection: rejection),
                           "rejection \(String(describing: rejection)) must not auto-retry")
        }
    }

    func testTimeoutRetainsRequestIdentityUntilCancelled() {
        let relay = WatchHRRelay()
        let request = UUID()
        relay.begin(requestID: request)
        relay.timeout()

        XCTAssertEqual(relay.activeRequestID, request,
                       "the phone still needs the request ID to stop a timed-out remote session")
        relay.cancel()
        XCTAssertNil(relay.activeRequestID)
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
