import Testing
import Foundation
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

@MainActor
@Suite final class WatchHRRelayTests {
    @Test func samplesFromAnOlderRequestAreRejected() {
        let relay = WatchHRRelay()
        let oldRequest = UUID()
        let currentRequest = UUID()
        let start = Date(timeIntervalSince1970: 100)
        relay.begin(requestID: currentRequest, now: start)

        #expect(!relay.receive(bpm: 140, requestID: oldRequest, now: start.addingTimeInterval(1)))
        #expect(relay.freshBPM(at: start.addingTimeInterval(1)) == nil)
        #expect(relay.receive(bpm: 141, requestID: currentRequest, now: start.addingTimeInterval(2)))
        #expect(relay.freshBPM(at: start.addingTimeInterval(2)) == 141)
    }

    @Test func liveHeartRateBecomesStaleAfterThreeMissedHeartbeats() {
        let relay = WatchHRRelay()
        let request = UUID()
        let start = Date(timeIntervalSince1970: 200)
        relay.begin(requestID: request, now: start)
        #expect(relay.receive(bpm: 132, requestID: request, now: start.addingTimeInterval(1)))
        #expect(relay.freshBPM(at: start.addingTimeInterval(16)) == 132)
        #expect(relay.freshBPM(at: start.addingTimeInterval(16.01)) == nil)
    }

    @Test func phoneLaunchedWatchAppStepsThroughLaunchingConnectingAndLive() {
        let relay = WatchHRRelay()
        let request = UUID()
        let start = Date(timeIntervalSince1970: 400)
        relay.begin(requestID: request, launchingWatchApp: true, now: start)
        #expect(relay.state == .launchingWatchApp(requestID: request, startedAt: start))
        relay.watchAppLaunched(now: start.addingTimeInterval(3))
        #expect(relay.state == .connecting(requestID: request, startedAt: start.addingTimeInterval(3)))
        relay.acknowledged(now: start.addingTimeInterval(4))
        #expect(relay.state == .waitingForSample(requestID: request, acknowledgedAt: start.addingTimeInterval(4)))
        #expect(relay.receive(bpm: 118, requestID: request, now: start.addingTimeInterval(6)))
        #expect(relay.freshBPM(at: start.addingTimeInterval(6)) == 118)
    }

    @Test func watchReplyCanBeatTheLaunchCallback() {
        let relay = WatchHRRelay()
        let request = UUID()
        let start = Date(timeIntervalSince1970: 500)
        relay.begin(requestID: request, launchingWatchApp: true, now: start)
        relay.acknowledged(now: start.addingTimeInterval(2))
        relay.watchAppLaunched(now: start.addingTimeInterval(3))
        #expect(relay.state == .waitingForSample(requestID: request, acknowledgedAt: start.addingTimeInterval(2)),
                       "a late launch callback must not step back to connecting")
    }

    @Test func firstSampleCanArriveWhileStillLaunching() {
        let relay = WatchHRRelay()
        let request = UUID()
        let start = Date(timeIntervalSince1970: 600)
        relay.begin(requestID: request, launchingWatchApp: true, now: start)
        #expect(!relay.receive(bpm: 120, requestID: UUID(), now: start.addingTimeInterval(1)))
        #expect(relay.receive(bpm: 120, requestID: request, now: start.addingTimeInterval(1)))
        #expect(relay.freshBPM(at: start.addingTimeInterval(1)) == 120)
    }

    @Test func timedOutRelayRecoversWhenTheSameWatchSessionResumes() {
        let relay = WatchHRRelay()
        let request = UUID()
        let start = Date(timeIntervalSince1970: 250)
        relay.begin(requestID: request, now: start)
        relay.acknowledged(now: start.addingTimeInterval(1))
        relay.timeout()

        #expect(relay.receive(bpm: 128, requestID: request, now: start.addingTimeInterval(20)))
        #expect(relay.freshBPM(at: start.addingTimeInterval(20)) == 128)
        #expect(!relay.receive(bpm: 128, requestID: UUID(), now: start.addingTimeInterval(20)))
    }

    @Test func everyRejectionHasAPlainMessage() {
        let all: [WatchHRRejection] = [.alreadyActive, .watchWorkoutActive, .unavailable,
                                       .unsupported, .healthPermissionDenied, .sessionStartFailed]
        for rejection in all {
            #expect(!rejection.userMessage.isEmpty)
            #expect(!rejection.userMessage.contains(rejection.rawValue),
                           "raw rejection codes are not user-facing text")
        }
    }

    @Test func alreadyActiveShouldRetryAfterStop() {
        #expect(WatchHRRelay.shouldRetryAfterStop(rejection: .alreadyActive))
    }

    @Test func nonRetryableRejectionsShouldNotRetry() {
        let nonRetryable: [WatchHRRejection?] = [.healthPermissionDenied, .unsupported,
                                                 .unavailable, .sessionStartFailed,
                                                 .watchWorkoutActive, nil]
        for rejection in nonRetryable {
            #expect(!WatchHRRelay.shouldRetryAfterStop(rejection: rejection),
                           "rejection \(String(describing: rejection)) must not auto-retry")
        }
    }

    @Test func timeoutRetainsRequestIdentityUntilCancelled() {
        let relay = WatchHRRelay()
        let request = UUID()
        relay.begin(requestID: request)
        relay.timeout()

        #expect(relay.activeRequestID == request,
                       "the phone still needs the request ID to stop a timed-out remote session")
        relay.cancel()
        #expect(relay.activeRequestID == nil)
    }

    @Test func relayRecoverySequence() {
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
        #expect(relay.receive(bpm: 138, requestID: retry, now: start.addingTimeInterval(4)))
        #expect(relay.freshBPM(at: start.addingTimeInterval(5)) == 138)
        #expect(relay.activeRequestID == retry)
    }
}
