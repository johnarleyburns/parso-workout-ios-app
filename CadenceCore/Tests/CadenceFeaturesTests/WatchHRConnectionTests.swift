import Foundation
import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchHRConnectionTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func ids() -> WatchHRConnectionIdentity { .init(phoneSessionID: UUID(), requestID: UUID()) }
    private func started(_ id: WatchHRConnectionIdentity) -> WatchHRConnection {
        var c = WatchHRConnection(); c.start(id, now: t0); return c
    }

    @Test func freshSampleMovesWatchdogDeadlineAndHeartbeatDoesNotRefreshSample() {
        let id = ids(); var c = started(id)
        _ = c.receiveSample(requestID: id.requestID, at: t0)
        #expect(c.isTransportLive(now: t0.addingTimeInterval(14)))
        #expect(c.isSampleFresh(now: t0.addingTimeInterval(14)))
        _ = c.receiveTransportHeartbeat(requestID: id.requestID, at: t0.addingTimeInterval(14))
        #expect(c.isTransportLive(now: t0.addingTimeInterval(28)))
        #expect(!c.isSampleFresh(now: t0.addingTimeInterval(28)))
    }

    @Test func healthyFirstWatchdogDoesNotDisableLaterStaleRecovery() {
        let id = ids(); var c = started(id)
        _ = c.receiveSample(requestID: id.requestID, at: t0)
        #expect(c.tick(now: t0.addingTimeInterval(16)) == .initialWaitElapsed)
        #expect(c.state == .reconciling(.initialWaitElapsed))
    }

    @Test func heartbeatForOtherRequestIsRejectedAndCannotKeepLinkLive() {
        let id = ids(); var c = started(id)
        #expect(c.receiveTransportHeartbeat(requestID: UUID(), at: t0) == .rejectedMismatch)
        #expect(!c.isTransportLive(now: t0))
    }

    @Test func nextWakeDelayNilAfterEndAndNonNilWhileAwaitingSample() {
        let id = ids(); var c = started(id)
        #expect(c.nextWakeDelay(now: t0) != nil)
        c.end()
        #expect(c.nextWakeDelay(now: t0) == nil)
    }

    @Test func launchFirstThenDurableCommandAdoptsAndBufferedHRGoesLiveOnce() {
        let id = ids()
        var c = started(id)
        c.watchLaunched()
        #expect(c.state == .awaitingWatchAdoption)
        var buffer = WatchHRUnclaimedBuffer()
        buffer.append(bpm: 120, sampleEnd: t0.addingTimeInterval(2), isHealthKit: true)
        buffer.append(bpm: 120, sampleEnd: t0.addingTimeInterval(2), isHealthKit: true)
        buffer.append(bpm: 90, sampleEnd: t0.addingTimeInterval(-500), isHealthKit: true)
        let didAdopt = c.adopted(id)
        #expect(didAdopt)
        let claimed = buffer.claim(from: t0, through: t0.addingTimeInterval(10))
        #expect(claimed.count == 1)
        #expect(buffer.isEmpty)
        #expect(c.receiveSample(requestID: id.requestID, at: t0.addingTimeInterval(3)) == .accepted)
        #expect(c.isLive(now: t0.addingTimeInterval(4)))
    }

    @Test func bufferIsBounded() {
        var buffer = WatchHRUnclaimedBuffer()
        for i in 0..<(WatchHRUnclaimedBuffer.capacity + 20) {
            buffer.append(bpm: 100, sampleEnd: t0.addingTimeInterval(Double(i)), isHealthKit: true)
        }
        #expect(buffer.readings.count == WatchHRUnclaimedBuffer.capacity)
        #expect(buffer.droppedCount == 20)
    }

    @Test func adoptionOfAnotherWorkoutsIdentityIsRefused() {
        let a = ids(), b = ids()
        var c = started(b)
        let didAdopt = c.adopted(a)
        #expect(!didAdopt)
        #expect(c.state == .startingWatchWorkout(b))
    }

    @Test func foregroundWaitTriggersReconcileNotSilence() {
        var c = started(ids())
        #expect(c.tick(now: t0.addingTimeInterval(WatchHRConnection.initialWait - 1)) == nil)
        #expect(c.tick(now: t0.addingTimeInterval(WatchHRConnection.initialWait)) == .initialWaitElapsed)
        #expect(c.state == .reconciling(.initialWaitElapsed))
    }

    @Test func staleRequestMismatchIsExplicitAndNeverLive() {
        let id = ids()
        var c = started(id)
        #expect(c.receiveSample(requestID: UUID(), at: t0) == .rejectedMismatch)
        #expect(!c.isLive(now: t0))
        #expect(c.diagnostics(now: t0).lastFailure == .requestMismatch)
    }

    @Test func reportDecisions() {
        let id = ids()
        let stale = UUID()
        func report(active: Bool = true, req: UUID? = nil, session: UUID? = nil, pending: Bool = false,
                    type: String? = "strength", v: Int = 2) -> WatchHRStateReport {
            .init(protocolVersion: v, isWorkoutActive: active, healthKitRunning: true, workoutType: type,
                  adoptedRequestID: req, adoptedPhoneSessionID: session, awaitingAdoption: pending)
        }
        #expect(WatchHRConnection.decide(report: report(req: id.requestID, session: id.phoneSessionID), expecting: id) == .accept)
        #expect(WatchHRConnection.decide(report: report(active: false), expecting: id) == .redeliverStart)
        #expect(WatchHRConnection.decide(report: report(pending: true), expecting: id) == .redeliverStart)
        #expect(WatchHRConnection.decide(report: report(req: stale), expecting: id) == .stopOrphan(requestID: stale))
        #expect(WatchHRConnection.decide(report: report(), expecting: id) == .conflict(.watchOnlyWorkoutActive))
        #expect(WatchHRConnection.decide(report: report(req: id.requestID, session: UUID()), expecting: id) == .conflict(.requestMismatch))
        #expect(WatchHRConnection.decide(report: report(v: 1), expecting: id) == .conflict(.protocolMismatch))
    }

    @Test func watchOnlyConflictOffersNoAutomaticRetry() {
        var c = started(ids())
        c.apply(.conflict(.watchOnlyWorkoutActive))
        #expect(c.state == .recoverableFailure(.watchOnlyWorkoutActive, retryAvailable: false))
    }

    @Test func reachabilityFlapsAreBoundedAndRecoverOnValidReport() {
        let id = ids()
        var c = started(id)
        var sent = 0
        for i in 0..<20 {
            if c.reachabilityOrActivation(.reachabilityChanged, now: t0.addingTimeInterval(Double(i))) != nil { sent += 1 }
        }
        #expect(sent == WatchHRConnection.maxAttempts)
        guard case .recoverableFailure(.retriesExhausted, true) = c.state else {
            Issue.record("\(c.state)")
            return
        }
        #expect(c.userReconnect(now: t0.addingTimeInterval(30)) != nil)
        c.apply(.accept)
        #expect(c.state == .awaitingFirstSample)
        #expect(c.receiveSample(requestID: id.requestID, at: t0.addingTimeInterval(31)) == .accepted)
    }

    @Test func stateReportRoundTripsAndOmitsBPM() {
        let r = WatchHRStateReport(isWorkoutActive: true, healthKitRunning: true, workoutType: "strength",
                                   adoptedRequestID: UUID(), adoptedPhoneSessionID: UUID(),
                                   lastRealSampleAt: t0, queryIssuedAt: 5)
        #expect(WatchHRStateReport(payload: r.payload) == r)
        #expect(r.payload["bpm"] == nil)
    }

    @Test func staleLiveExpiresAndNewConnectionDoesNotInherit() {
        let id = ids()
        var c = started(id)
        _ = c.receiveSample(requestID: id.requestID, at: t0)
        #expect(!c.isLive(now: t0.addingTimeInterval(WatchHRRelay.staleAfter + 1)))
        c.end()
        let next = ids()
        c.start(next, now: t0.addingTimeInterval(100))
        #expect(c.displayedSampleAge(now: t0.addingTimeInterval(101)) == nil)
        #expect(c.receiveSample(requestID: id.requestID, at: t0.addingTimeInterval(102)) == .rejectedMismatch)
    }

    @Test func endedConnectionRejectsDelayedSamples() {
        let id = ids()
        var c = started(id)
        c.end()
        #expect(c.receiveSample(requestID: id.requestID, at: t0) == .rejectedInactive)
    }

    @Test func queryCommandRoundTrips() {
        let q = WatchHRCommand(action: .query, requestID: nil, issuedAt: 9)
        #expect(WatchHRCommand(payload: q.payload) == q)
    }

    @Test func isCapturingReturnsTrueForSameSessionWhileAwaitingFirstSample() {
        let identity = ids()
        var connection = WatchHRConnection()
        connection.start(identity, now: t0)
        #expect(connection.isCapturing(sessionID: identity.phoneSessionID))
    }

    @Test func isCapturingReturnsFalseForDifferentOrTerminalSession() {
        let identity = ids()
        var connection = WatchHRConnection()
        connection.start(identity, now: t0)
        #expect(!connection.isCapturing(sessionID: UUID()))
        connection.end()
        #expect(!connection.isCapturing(sessionID: identity.phoneSessionID))
    }

    @Test func reconcileStepIsReachableFromPacketArrivalWithoutTimer() {
        let id = ids(); var c = started(id)
        _ = c.receiveSample(requestID: id.requestID, at: t0)
        // Timer never fired (phone locked); a later packet triggers the pass.
        let late = t0.addingTimeInterval(60)
        let step = c.reconcileStep(now: late, externalBPMVisible: true)
        #expect(step.query == .initialWaitElapsed)
        #expect(step.clearStaleBPM)
        // Nothing visible -> nothing to clear; not yet due -> no query.
        var d = started(id)
        _ = d.receiveSample(requestID: id.requestID, at: t0)
        let early = d.reconcileStep(now: t0.addingTimeInterval(1), externalBPMVisible: false)
        #expect(early.query == nil)
        #expect(!early.clearStaleBPM)
    }
}
