import XCTest
@testable import CadenceFeatures

final class WatchHRLivePromotionTests: XCTestCase {
    private let session = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let request = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func obs(_ n: Int, end: TimeInterval, bpm: Double) -> WatchHRObservation {
        WatchHRObservation(
            observationID: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")!,
            source: .watchHealthKit, sampleEnd: end, bpm: bpm)
    }

    private func message(kind: WatchHRMessageKind = .observations,
                         session: UUID? = nil, request: UUID? = nil,
                         observations: [WatchHRObservation]) -> WatchHRMessage {
        WatchHRMessage(kind: kind, deliveryID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                       phoneWorkoutSessionID: session ?? self.session,
                       watchRequestID: request ?? self.request,
                       captureEpoch: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                       sequence: 1, observations: observations)
    }

    private func select(_ m: WatchHRMessage, session: UUID?, request: UUID?) -> WatchHRObservation? {
        WatchHRLivePromotion.newestFreshObservation(in: m, activeSessionID: session,
                                                    activeRequestID: request, now: now)
    }

    func testPromotesNewestFreshObservationForMatchingCapture() {
        let t = now.timeIntervalSince1970
        let m = message(observations: [obs(1, end: t - 5, bpm: 150), obs(2, end: t - 20, bpm: 120),
                                       obs(3, end: t - 10, bpm: 140)])
        XCTAssertEqual(select(m, session: session, request: request)?.bpm, 150)
    }

    func testRejectsDifferentSessionOrRequest() {
        let m = message(observations: [obs(1, end: now.timeIntervalSince1970 - 1, bpm: 130)])
        XCTAssertNil(select(m, session: UUID(), request: request))
        XCTAssertNil(select(m, session: session, request: UUID()))
        XCTAssertNil(select(m, session: nil, request: nil))
    }

    func testRejectsObservationOlderThanStaleWindow() {
        let old = now.timeIntervalSince1970 - WatchHRRelay.staleAfter - 1
        let m = message(observations: [obs(1, end: old, bpm: 130)])
        XCTAssertNil(select(m, session: session, request: request))
    }

    func testRejectsFinalizeAndEmptyObservationMessages() {
        let o = [obs(1, end: now.timeIntervalSince1970 - 1, bpm: 130)]
        XCTAssertNil(select(message(kind: .finalizeRequest, observations: o), session: session, request: request))
        XCTAssertNil(select(message(kind: .finalizeAcknowledgement, observations: o), session: session, request: request))
        XCTAssertNil(select(message(observations: []), session: session, request: request))
    }
}
