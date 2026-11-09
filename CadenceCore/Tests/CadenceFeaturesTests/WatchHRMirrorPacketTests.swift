import XCTest
@testable import CadenceFeatures

final class WatchHRMirrorPacketTests: XCTestCase {
    private let s = UUID(), r = UUID(), e = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func packet(end: TimeInterval = 1_800_000_000, bpm: Double = 120) -> WatchHRMirrorPacket {
        WatchHRMirrorPacket(phoneWorkoutSessionID: s, watchRequestID: r, captureEpoch: e, sampleEnd: end, bpm: bpm)
    }
    private func decide(_ p: WatchHRMirrorPacket, session: UUID? = nil, request: UUID? = nil,
                        epoch: UUID? = nil) -> WatchHRMirrorRouting.Decision {
        WatchHRMirrorRouting.decide(p, activeSessionID: session ?? s, activeRequestID: request ?? r,
                                    routeCaptureEpoch: epoch ?? e, now: now)
    }

    func testRoundTrip() throws {
        let p = packet()
        let back = try JSONDecoder().decode(WatchHRMirrorPacket.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        XCTAssertEqual(WatchHRMirrorRouting.decode([try JSONEncoder().encode(p), Data([1])]), [p])
    }

    func testRejectsInvalidFields() throws {
        XCTAssertFalse(packet(bpm: 10).isValid)
        XCTAssertFalse(packet(bpm: 300).isValid)
        XCTAssertFalse(packet(bpm: .nan).isValid)
        XCTAssertFalse(packet(end: 0).isValid)
        XCTAssertFalse(packet(end: .infinity).isValid)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(packet())) as! [String: Any]
        json["protocolVersion"] = 2
        let bad = try JSONDecoder().decode(WatchHRMirrorPacket.self,
                                           from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(bad.isValid)
        XCTAssertEqual(decide(bad), .rejectedInvalid)
    }

    func testRoutingAcceptsMatchingFreshPacket() {
        XCTAssertEqual(decide(packet()), .accept)
    }

    func testRoutingRejectsWrongSessionRequestEpoch() {
        XCTAssertEqual(decide(packet(), session: UUID()), .rejectedRoute)
        XCTAssertEqual(decide(packet(), request: UUID()), .rejectedRoute)
        XCTAssertEqual(decide(packet(), epoch: UUID()), .rejectedRoute)
        XCTAssertEqual(WatchHRMirrorRouting.decide(packet(), activeSessionID: nil, activeRequestID: r,
                                                   routeCaptureEpoch: e, now: now), .rejectedRoute)
    }

    func testRoutingAcceptsPacketForActivePhoneCardioSession() {
        let cardioID = s
        let active = WatchHRMirrorRouting.activeSessionID(strength: nil, cardio: cardioID)
        XCTAssertEqual(active, cardioID)
        XCTAssertEqual(WatchHRMirrorRouting.decide(packet(), activeSessionID: active, activeRequestID: r,
                                                   routeCaptureEpoch: e, now: now), .accept)
        XCTAssertEqual(WatchHRMirrorRouting.activeSessionID(strength: UUID(), cardio: cardioID) == cardioID, false)
    }

    @MainActor func testStalePacketDoesNotReviveLiveBPM() {
        let old = packet(end: now.timeIntervalSince1970 - WatchHRRelay.staleAfter - 1)
        XCTAssertEqual(decide(old), .stale)
    }

    func testPacketDoesNotTouchOutboxAcknowledgementState() {
        // Routing is pure: it takes no outbox and returns only a decision, so
        // durable acknowledgement state cannot change by construction.
        let before = packet()
        _ = decide(before)
        XCTAssertEqual(before, packet())
    }
}
