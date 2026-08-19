//
//  Cadence_Watch_App_Watch_AppTests.swift
//  Cadence Watch App Watch AppTests
//
//  Created by Arley on 6/4/26.
//

import Testing
import HealthKit
import WatchKit
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

    /// HealthKit calls this the instant a workout session starts, on its own
    /// queue. While the conformance was `@preconcurrency` on a `@MainActor`
    /// class, Swift 6's dynamic isolation check trapped here and killed the app —
    /// which is what broke Live HR, the phone's HR request, and resuming a
    /// strength workout. Entering from a background queue must simply return.
    @Test func workoutSessionStateChangeCanEnterFromHealthKitQueue() async {
        let manager = await MainActor.run { WatchWorkoutManager(uiTestMode: true) }
        let callbackReturned = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [manager] in
                let delegate: any HKWorkoutSessionDelegate = manager
                let configuration = HKWorkoutConfiguration()
                configuration.activityType = .other
                guard let session = try? HKWorkoutSession(healthStore: HKHealthStore(),
                                                          configuration: configuration) else {
                    continuation.resume(returning: false)
                    return
                }
                delegate.workoutSession(session, didChangeTo: .running, from: .notStarted, date: Date())
                continuation.resume(returning: true)
            }
        }

        #expect(callbackReturned)
    }

    /// The same boundary for the live builder, which delivers HR and distance.
    @Test func builderEventCallbackCanEnterFromHealthKitQueue() async {
        let manager = await MainActor.run { WatchWorkoutManager(uiTestMode: true) }
        let callbackReturned = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [manager] in
                let delegate: any HKLiveWorkoutBuilderDelegate = manager
                let configuration = HKWorkoutConfiguration()
                configuration.activityType = .other
                guard let session = try? HKWorkoutSession(healthStore: HKHealthStore(),
                                                          configuration: configuration) else {
                    continuation.resume(returning: false)
                    return
                }
                delegate.workoutBuilderDidCollectEvent(session.associatedWorkoutBuilder())
                continuation.resume(returning: true)
            }
        }

        #expect(callbackReturned)
    }

    /// WatchKit delivers extended-runtime callbacks off the main actor too.
    @Test func extendedRuntimeCallbackCanEnterFromWatchKitQueue() async {
        let manager = await MainActor.run { WatchWorkoutManager(uiTestMode: true) }
        let callbackReturned = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [manager] in
                let delegate: any WKExtendedRuntimeSessionDelegate = manager
                delegate.extendedRuntimeSessionDidStart(WKExtendedRuntimeSession())
                continuation.resume(returning: true)
            }
        }

        #expect(callbackReturned)
    }

}
