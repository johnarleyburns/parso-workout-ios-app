import XCTest
@testable import CadenceFeatures

final class WatchHRConnectionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func ids() -> WatchHRConnectionIdentity { .init(phoneSessionID: UUID(), requestID: UUID()) }
    private func started(_ id: WatchHRConnectionIdentity) -> WatchHRConnection {
        var c = WatchHRConnection(); c.start(id, now: t0); return c
    }

    func testFreshSampleMovesWatchdogDeadlineAndHeartbeatDoesNotRefreshSample() {
        let id = ids(); var c = started(id)
        _ = c.receiveSample(requestID: id.requestID, at: t0)
        XCTAssertTrue(c.isTransportLive(now: t0.addingTimeInterval(14)))
        XCTAssertTrue(c.isSampleFresh(now: t0.addingTimeInterval(14)))
        _ = c.receiveTransportHeartbeat(requestID: id.requestID, at: t0.addingTimeInterval(14))
        XCTAssertTrue(c.isTransportLive(now: t0.addingTimeInterval(28)))
        XCTAssertFalse(c.isSampleFresh(now: t0.addingTimeInterval(28)))
    }

    func testHealthyFirstWatchdogDoesNotDisableLaterStaleRecovery() {
        let id = ids(); var c = started(id)
        _ = c.receiveSample(requestID: id.requestID, at: t0)
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(16)), .initialWaitElapsed)
        XCTAssertEqual(c.state, .reconciling(.initialWaitElapsed))
    }

    func testHeartbeatForOtherRequestIsRejectedAndCannotKeepLinkLive() {
        let id = ids(); var c = started(id)
        XCTAssertEqual(c.receiveTransportHeartbeat(requestID: UUID(), at: t0), .rejectedMismatch)
        XCTAssertFalse(c.isTransportLive(now: t0))
    }

    func testNextWakeDelayNilAfterEndAndNonNilWhileAwaitingSample() {
        let id = ids(); var c = started(id)
        XCTAssertNotNil(c.nextWakeDelay(now: t0))
        c.end()
        XCTAssertNil(c.nextWakeDelay(now: t0))
    }

    func testLaunchFirstThenDurableCommandAdoptsAndBufferedHRGoesLiveOnce() {
        let id = ids()
        var c = started(id)
        c.watchLaunched()
        XCTAssertEqual(c.state, .awaitingWatchAdoption)
        var buffer = WatchHRUnclaimedBuffer()
        buffer.append(bpm: 120, sampleEnd: t0.addingTimeInterval(2), isHealthKit: true)
        buffer.append(bpm: 120, sampleEnd: t0.addingTimeInterval(2), isHealthKit: true)
        buffer.append(bpm: 90, sampleEnd: t0.addingTimeInterval(-500), isHealthKit: true)
        XCTAssertTrue(c.adopted(id))
        let claimed = buffer.claim(from: t0, through: t0.addingTimeInterval(10))
        XCTAssertEqual(claimed.count, 1)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(c.receiveSample(requestID: id.requestID, at: t0.addingTimeInterval(3)), .accepted)
        XCTAssertTrue(c.isLive(now: t0.addingTimeInterval(4)))
    }

    func testBufferIsBounded() {
        var buffer = WatchHRUnclaimedBuffer()
        for i in 0..<(WatchHRUnclaimedBuffer.capacity + 20) {
            buffer.append(bpm: 100, sampleEnd: t0.addingTimeInterval(Double(i)), isHealthKit: true)
        }
        XCTAssertEqual(buffer.readings.count, WatchHRUnclaimedBuffer.capacity)
        XCTAssertEqual(buffer.droppedCount, 20)
    }

    func testAdoptionOfAnotherWorkoutsIdentityIsRefused() {
        let a = ids(), b = ids()
        var c = started(b)
        XCTAssertFalse(c.adopted(a))
        XCTAssertEqual(c.state, .startingWatchWorkout(b))
    }

    func testForegroundWaitTriggersReconcileNotSilence() {
        var c = started(ids())
        XCTAssertNil(c.tick(now: t0.addingTimeInterval(WatchHRConnection.initialWait - 1)))
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(WatchHRConnection.initialWait)), .initialWaitElapsed)
        XCTAssertEqual(c.state, .reconciling(.initialWaitElapsed))
    }

    func testStaleRequestMismatchIsExplicitAndNeverLive() {
        let id = ids()
        var c = started(id)
        XCTAssertEqual(c.receiveSample(requestID: UUID(), at: t0), .rejectedMismatch)
        XCTAssertFalse(c.isLive(now: t0))
        XCTAssertEqual(c.diagnostics(now: t0).lastFailure, .requestMismatch)
    }

    func testReportDecisions() {
        let id = ids()
        let stale = UUID()
        func report(active: Bool = true, req: UUID? = nil, session: UUID? = nil, pending: Bool = false,
                    type: String? = "strength", v: Int = 2) -> WatchHRStateReport {
            .init(protocolVersion: v, isWorkoutActive: active, healthKitRunning: true, workoutType: type,
                  adoptedRequestID: req, adoptedPhoneSessionID: session, awaitingAdoption: pending)
        }
        XCTAssertEqual(WatchHRConnection.decide(report: report(req: id.requestID, session: id.phoneSessionID), expecting: id), .accept)
        XCTAssertEqual(WatchHRConnection.decide(report: report(active: false), expecting: id), .redeliverStart)
        XCTAssertEqual(WatchHRConnection.decide(report: report(pending: true), expecting: id), .redeliverStart)
        XCTAssertEqual(WatchHRConnection.decide(report: report(req: stale), expecting: id), .stopOrphan(requestID: stale))
        XCTAssertEqual(WatchHRConnection.decide(report: report(), expecting: id), .conflict(.watchOnlyWorkoutActive))
        XCTAssertEqual(WatchHRConnection.decide(report: report(req: id.requestID, session: UUID()), expecting: id), .conflict(.requestMismatch))
        XCTAssertEqual(WatchHRConnection.decide(report: report(v: 1), expecting: id), .conflict(.protocolMismatch))
    }

    func testWatchOnlyConflictOffersNoAutomaticRetry() {
        var c = started(ids())
        c.apply(.conflict(.watchOnlyWorkoutActive))
        XCTAssertEqual(c.state, .recoverableFailure(.watchOnlyWorkoutActive, retryAvailable: false))
    }

    func testReachabilityFlapsAreBoundedAndRecoverOnValidReport() {
        let id = ids()
        var c = started(id)
        var sent = 0
        for i in 0..<20 {
            if c.reachabilityOrActivation(.reachabilityChanged, now: t0.addingTimeInterval(Double(i))) != nil { sent += 1 }
        }
        XCTAssertEqual(sent, WatchHRConnection.maxAttempts)
        guard case .recoverableFailure(.retriesExhausted, true) = c.state else { return XCTFail("\(c.state)") }
        XCTAssertNotNil(c.userReconnect(now: t0.addingTimeInterval(30)))
        c.apply(.accept)
        XCTAssertEqual(c.state, .awaitingFirstSample)
        XCTAssertEqual(c.receiveSample(requestID: id.requestID, at: t0.addingTimeInterval(31)), .accepted)
    }

    func testStateReportRoundTripsAndOmitsBPM() {
        let r = WatchHRStateReport(isWorkoutActive: true, healthKitRunning: true, workoutType: "strength",
                                   adoptedRequestID: UUID(), adoptedPhoneSessionID: UUID(),
                                   lastRealSampleAt: t0, queryIssuedAt: 5)
        XCTAssertEqual(WatchHRStateReport(payload: r.payload), r)
        XCTAssertNil(r.payload["bpm"])
    }

    func testStaleLiveExpiresAndNewConnectionDoesNotInherit() {
        let id = ids()
        var c = started(id)
        _ = c.receiveSample(requestID: id.requestID, at: t0)
        XCTAssertFalse(c.isLive(now: t0.addingTimeInterval(WatchHRRelay.staleAfter + 1)))
        c.end()
        let next = ids()
        c.start(next, now: t0.addingTimeInterval(100))
        XCTAssertNil(c.displayedSampleAge(now: t0.addingTimeInterval(101)))
        XCTAssertEqual(c.receiveSample(requestID: id.requestID, at: t0.addingTimeInterval(102)), .rejectedMismatch)
    }

    func testEndedConnectionRejectsDelayedSamples() {
        let id = ids()
        var c = started(id)
        c.end()
        XCTAssertEqual(c.receiveSample(requestID: id.requestID, at: t0), .rejectedInactive)
    }

    func testQueryCommandRoundTrips() {
        let q = WatchHRCommand(action: .query, requestID: nil, issuedAt: 9)
        XCTAssertEqual(WatchHRCommand(payload: q.payload), q)
    }
}
