import XCTest
import WatchConnectivity
@testable import Cadence

final class AppModelWCSessionDelegateTests: XCTestCase {
    func testActivationCallbackCanEnterFromWatchConnectivityQueue() async {
        let model = await MainActor.run { AppModel() }
        let callbackReturned = expectation(description: "WCSession activation callback returned")

        DispatchQueue.global(qos: .userInitiated).async { [model] in
            // WatchConnectivity delivers delegate callbacks on a private operation
            // queue. Calling through the Objective-C protocol existential mirrors
            // that framework boundary and catches accidental actor isolation on
            // the delegate entry point.
            let delegate: any WCSessionDelegate = model
            delegate.session(
                WCSession.default,
                activationDidCompleteWith: .activated,
                error: nil
            )
            callbackReturned.fulfill()
        }

        await fulfillment(of: [callbackReturned], timeout: 2)
    }
}
