import XCTest
@preconcurrency import WatchConnectivity
import CadenceFeatures
@testable import Cadence

final class AppModelWCSessionDelegateTests: XCTestCase {
    @MainActor
    func testHomePlanUpdateUsesCacheForLaterForegroundSync() {
        let model = AppModel()
        let plan = WatchSync.TodayPlan(sessions: [
            .init(id: "strength-0", kind: .strength, label: "Upper body")
        ])

        model.updateWatchTodayPlan(plan)

        XCTAssertEqual(model.cachedTodayPlanForTesting, plan)
    }

    @MainActor
    func testDurableBatchWithoutActiveCaptureLeavesLiveStateUntouched() {
        let model = AppModel()
        let request = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        model.watchHRRelay.begin(requestID: request)
        let message = WatchHRMessage(
            kind: .observations, deliveryID: UUID(),
            phoneWorkoutSessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            watchRequestID: request, captureEpoch: UUID(), sequence: 1,
            observations: [WatchHRObservation(observationID: UUID(), source: .watchHealthKit,
                                              sampleEnd: Date().timeIntervalSince1970, bpm: 140)])

        model.promoteDurableWatchHR(message, now: Date())

        XCTAssertNil(model.watchHRRelay.freshBPM)
        XCTAssertFalse(model.watchActive)
    }

    func testActivationCallbackCanEnterFromWatchConnectivityQueue() async {
        let model = await MainActor.run { AppModel() }
        let delegate = await MainActor.run {
            SendableDelegateBox(model.watchSessionDelegateForTesting)
        }
        let callbackReturned = expectation(description: "WCSession activation callback returned")

        DispatchQueue.global(qos: .userInitiated).async {
            // WatchConnectivity delivers delegate callbacks on a private operation
            // queue. Calling through the Objective-C protocol existential mirrors
            // that framework boundary and catches accidental actor isolation on
            // the delegate entry point.
            delegate.value.session(
                WCSession.default,
                activationDidCompleteWith: .activated,
                error: nil
            )
            callbackReturned.fulfill()
        }

        await fulfillment(of: [callbackReturned], timeout: 2)
    }
}

private final class SendableDelegateBox: @unchecked Sendable {
    let value: any WCSessionDelegate

    init(_ value: any WCSessionDelegate) {
        self.value = value
    }
}
