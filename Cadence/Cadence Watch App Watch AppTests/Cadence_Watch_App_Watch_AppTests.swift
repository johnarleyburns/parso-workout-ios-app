//
//  Cadence_Watch_App_Watch_AppTests.swift
//  Cadence Watch App Watch AppTests
//
//  Created by Arley on 6/4/26.
//

import Testing
import WatchConnectivity
@testable import Cadence_Watch_App_Watch_App

struct Cadence_Watch_App_Watch_AppTests {

    @Test func activationCallbackCanEnterFromWatchConnectivityQueue() async {
        let manager = await MainActor.run {
            WatchWorkoutManager(uiTestMode: true)
        }
        let callbackReturned = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [manager] in
                // WatchConnectivity delivers delegate callbacks on a private
                // operation queue. Calling through the protocol existential
                // mirrors that framework boundary.
                let delegate: any WCSessionDelegate = manager
                delegate.session(
                    WCSession.default,
                    activationDidCompleteWith: .activated,
                    error: nil
                )
                continuation.resume(returning: true)
            }
        }

        #expect(callbackReturned)
    }

}
