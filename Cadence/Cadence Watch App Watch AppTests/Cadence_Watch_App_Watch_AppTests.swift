//
//  Cadence_Watch_App_Watch_AppTests.swift
//  Cadence Watch App Watch AppTests
//
//  Created by Arley on 6/4/26.
//

import Testing
import HealthKit
import WatchConnectivity
import CadenceFeatures
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

    @Test func pollingRefreshDoesNotDoubleCountHeartRateAggregate() async {
        await MainActor.run {
            let manager = WatchWorkoutManager(uiTestMode: true)
            #expect(manager.startWorkout(type: "run"))
            manager.handleSessionStateChange(.running)
            #expect(manager.isHeartRatePollingForTesting)
            manager.apply(.init(bpm: 120, distanceMeters: nil))
            manager.applyPolledHeartRate(124)
            manager.applyPolledHeartRate(124)

            #expect(manager.currentBPM == 124)
            #expect(manager.liveSummary().avgHR == 120)
            manager.stopWorkout(save: false)
            #expect(!manager.isHeartRatePollingForTesting)
        }
    }

    @Test func visibleStopEndsPhoneStartedWorkout() async {
        await MainActor.run {
            let manager = WatchWorkoutManager(uiTestMode: true)
            #expect(manager.startWorkout(type: "run", phoneRequestID: UUID()))
            #expect(manager.isActive)
            manager.stopWorkout(save: false)
            #expect(!manager.isActive)
            #expect(!manager.isMonitoring)
        }
    }

    @Test func delayedQueuedStopCannotEndNewerPhoneWorkout() async {
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "watchHR.lastAppliedCommandAt")
            let manager = WatchWorkoutManager(uiTestMode: true)
            let firstID = UUID()
            let secondID = UUID()
            let start1 = WatchHRCommand(action: .start, requestID: firstID,
                                        workoutType: "run", issuedAt: 100)
            let stop1 = WatchHRCommand(action: .stop, requestID: firstID, issuedAt: 101)
            let start2 = WatchHRCommand(action: .start, requestID: secondID,
                                        workoutType: "cycle", issuedAt: 102)

            #expect(manager.handleMessage(start1.payload)["accepted"] as? Bool == true)
            #expect(manager.handleMessage(stop1.payload)["ack"] as? Bool == true)
            #expect(manager.handleMessage(start2.payload)["accepted"] as? Bool == true)
            #expect(manager.handleMessage(stop1.payload)["ack"] as? Bool == true)
            #expect(manager.isActive, "the delayed duplicate belongs to the older session")
            #expect(manager.workoutType == "cycle")
            manager.stopWorkout(save: false)
            UserDefaults.standard.removeObject(forKey: "watchHR.lastAppliedCommandAt")
        }
    }

    @Test func duplicateImmediateAndQueuedStartIsIdempotent() async {
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "watchHR.lastAppliedCommandAt")
            let manager = WatchWorkoutManager(uiTestMode: true)
            let requestID = UUID()
            let command = WatchHRCommand(action: .start, requestID: requestID,
                                         workoutType: "other", issuedAt: 300)

            let first = manager.handleMessage(command.payload)
            let duplicate = manager.handleMessage(command.payload)

            #expect(first["accepted"] as? Bool == true)
            #expect(duplicate["accepted"] as? Bool == true)
            #expect(duplicate["requestID"] as? String == requestID.uuidString)
            #expect(manager.isActive)
            manager.stopWorkout(save: false)
            UserDefaults.standard.removeObject(forKey: "watchHR.lastAppliedCommandAt")
        }
    }

    @Test func phoneRequestDoesNotTakeOverWatchOnlyWorkout() async {
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "watchHR.lastAppliedCommandAt")
            let manager = WatchWorkoutManager(uiTestMode: true)
            #expect(manager.startWorkout(type: "strength"))
            let requestID = UUID()
            let command = WatchHRCommand(action: .start, requestID: requestID,
                                         workoutType: "run", issuedAt: 200)
            let reply = manager.handleMessage(command.payload)

            #expect(reply["accepted"] as? Bool == false)
            #expect(reply["rejection"] as? String == WatchHRRejection.watchWorkoutActive.rawValue)
            manager.stopWorkout(save: false)
            UserDefaults.standard.removeObject(forKey: "watchHR.lastAppliedCommandAt")
        }
    }

    // MARK: - Phone opens the Watch app

    @MainActor
    private func runConfiguration() -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        return configuration
    }

    @Test func phoneLaunchStartsTheWorkoutAndTheQueuedCommandAdoptsIt() async {
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "watchHR.lastAppliedCommandAt")
            let manager = WatchWorkoutManager(uiTestMode: true)
            manager.startPhoneLaunchedWorkout(configuration: runConfiguration())
            #expect(manager.isActive, "the launch starts the workout before any command arrives")
            #expect(manager.phoneRequestID == nil)

            let requestID = UUID()
            let command = WatchHRCommand(action: .start, requestID: requestID,
                                         workoutType: "run", issuedAt: 400)
            let reply = manager.handleMessage(command.payload)
            #expect(reply["accepted"] as? Bool == true)
            #expect(manager.phoneRequestID == requestID.uuidString)

            let duplicate = manager.handleMessage(command.payload)
            #expect(duplicate["accepted"] as? Bool == true, "the immediate and queued copies are one command")

            let stop = WatchHRCommand(action: .stop, requestID: requestID, issuedAt: 401)
            #expect(manager.handleMessage(stop.payload)["ack"] as? Bool == true)
            #expect(!manager.isActive)
            UserDefaults.standard.removeObject(forKey: "watchHR.lastAppliedCommandAt")
        }
    }

    @Test func commandFirstThenLaunchKeepsOneWorkout() async {
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "watchHR.lastAppliedCommandAt")
            let manager = WatchWorkoutManager(uiTestMode: true)
            let requestID = UUID()
            let command = WatchHRCommand(action: .start, requestID: requestID,
                                         workoutType: "run", issuedAt: 500)
            #expect(manager.handleMessage(command.payload)["accepted"] as? Bool == true)
            manager.startPhoneLaunchedWorkout(configuration: runConfiguration())
            #expect(manager.isActive)
            #expect(manager.phoneRequestID == requestID.uuidString, "the late launch must not replace the request")
            manager.stopWorkout(save: false)
            UserDefaults.standard.removeObject(forKey: "watchHR.lastAppliedCommandAt")
        }
    }

    @Test func launchDuringAWatchWorkoutIsIgnored() async {
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "watchHR.lastAppliedCommandAt")
            let manager = WatchWorkoutManager(uiTestMode: true)
            #expect(manager.startWorkout(type: "strength"))
            manager.startPhoneLaunchedWorkout(configuration: runConfiguration())
            #expect(manager.workoutType == "strength")
            let command = WatchHRCommand(action: .start, requestID: UUID(),
                                         workoutType: "run", issuedAt: 600)
            let reply = manager.handleMessage(command.payload)
            #expect(reply["accepted"] as? Bool == false)
            #expect(reply["rejection"] as? String == WatchHRRejection.watchWorkoutActive.rawValue)
            manager.stopWorkout(save: false)
            UserDefaults.standard.removeObject(forKey: "watchHR.lastAppliedCommandAt")
        }
    }

    @Test func newReadingArmsOneRelayTimerAndStopDisarmsIt() async {
        await MainActor.run {
            let manager = WatchWorkoutManager(uiTestMode: true)
            #expect(manager.startWorkout(type: "run", phoneRequestID: UUID()))
            #expect(!manager.isHeartRateRelayArmedForTesting, "nothing runs before the first reading")
            manager.applyPolledHeartRate(120, sampleEnd: Date())
            #expect(manager.isHeartRateRelayArmedForTesting, "the heartbeat is armed after a reading")
            manager.stopWorkout(save: false)
            #expect(!manager.isHeartRateRelayArmedForTesting)
        }
    }

    @Test func watchOnlyWorkoutNeverArmsThePhoneRelay() async {
        await MainActor.run {
            let manager = WatchWorkoutManager(uiTestMode: true)
            #expect(manager.startWorkout(type: "run"))
            manager.applyPolledHeartRate(120, sampleEnd: Date())
            #expect(!manager.isHeartRateRelayArmedForTesting)
            manager.stopWorkout(save: false)
        }
    }

    @Test func screenOffPausesTheDisplayRefreshOnly() async {
        await MainActor.run {
            let manager = WatchWorkoutManager(uiTestMode: true)
            #expect(manager.startWorkout(type: "run", phoneRequestID: UUID()))
            manager.setDisplayActive(true)
            manager.handleSessionStateChange(.running)
            #expect(manager.isHeartRatePollingForTesting)
            manager.applyPolledHeartRate(118, sampleEnd: Date())
            manager.setDisplayActive(false)
            #expect(!manager.isHeartRatePollingForTesting)
            #expect(manager.isHeartRateRelayArmedForTesting, "the phone relay keeps running with the screen off")
            manager.setDisplayActive(true)
            #expect(manager.isHeartRatePollingForTesting)
            manager.stopWorkout(save: false)
        }
    }

}
