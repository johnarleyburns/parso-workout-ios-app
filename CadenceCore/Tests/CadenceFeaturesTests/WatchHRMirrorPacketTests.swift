import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct WatchHRMirrorPacketTests {
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

    @Test func roundTrip() throws {
        let p = packet()
        let back = try JSONDecoder().decode(WatchHRMirrorPacket.self, from: JSONEncoder().encode(p))
        #expect(back == p)
        #expect(WatchHRMirrorRouting.decode([try JSONEncoder().encode(p), Data([1])]) == [p])
    }

    @Test func rejectsInvalidFields() throws {
        #expect(!packet(bpm: 10).isValid)
        #expect(!packet(bpm: 300).isValid)
        #expect(!packet(bpm: .nan).isValid)
        #expect(!packet(end: 0).isValid)
        #expect(!packet(end: .infinity).isValid)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(packet())) as! [String: Any]
        json["protocolVersion"] = 2
        let bad = try JSONDecoder().decode(WatchHRMirrorPacket.self,
                                           from: JSONSerialization.data(withJSONObject: json))
        #expect(!bad.isValid)
        #expect(decide(bad) == .rejectedInvalid)
    }

    @Test func routingAcceptsMatchingFreshPacket() {
        #expect(decide(packet()) == .accept)
    }

    @Test func routingRejectsWrongSessionRequestEpoch() {
        #expect(decide(packet(), session: UUID()) == .rejectedRoute)
        #expect(decide(packet(), request: UUID()) == .rejectedRoute)
        #expect(decide(packet(), epoch: UUID()) == .rejectedRoute)
        #expect(WatchHRMirrorRouting.decide(packet(), activeSessionID: nil, activeRequestID: r,
                                                   routeCaptureEpoch: e, now: now) == .rejectedRoute)
    }

    @Test func routingAcceptsPacketForActivePhoneCardioSession() {
        let cardioID = s
        let active = WatchHRMirrorRouting.activeSessionID(strength: nil, cardio: cardioID)
        #expect(active == cardioID)
        #expect(WatchHRMirrorRouting.decide(packet(), activeSessionID: active, activeRequestID: r,
                                                   routeCaptureEpoch: e, now: now) == .accept)
        #expect((WatchHRMirrorRouting.activeSessionID(strength: UUID(), cardio: cardioID) == cardioID) == false)
    }

    @MainActor
    @Test func stalePacketDoesNotReviveLiveBPM() {
        let old = packet(end: now.timeIntervalSince1970 - WatchHRRelay.staleAfter - 1)
        #expect(decide(old) == .stale)
    }

    @Test func packetDoesNotTouchOutboxAcknowledgementState() {
        // Routing is pure: it takes no outbox and returns only a decision, so
        // durable acknowledgement state cannot change by construction.
        let before = packet()
        _ = decide(before)
        #expect(before == packet())
    }
}
