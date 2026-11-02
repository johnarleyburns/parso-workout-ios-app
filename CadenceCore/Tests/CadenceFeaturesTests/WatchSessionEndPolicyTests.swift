import XCTest
import CadenceCore
import CadenceFeatures

/// Authenticated, idempotent completion policy (issue #482).
final class WatchSessionEndPolicyTests: XCTestCase {
    private let deadline = Date(timeIntervalSince1970: 1_800_000_000)

    private func route(_ s: UUID) -> WatchStrengthCompletionRoute {
        WatchStrengthCompletionRoute(sessionID: s, transferID: UUID(), captureEpoch: UUID())
    }
    private func inactivity(_ s: UUID, id: UUID = UUID(), end: Date? = nil, dl: Date? = nil,
                            route: WatchStrengthCompletionRoute?) -> StrengthCompletionEnvelope {
        StrengthCompletionEnvelope(sessionID: s, reason: .inactivity, endedAt: end ?? deadline,
                                   inactivityDeadline: dl ?? deadline, completionID: id, version: 2, route: route)
    }
    private func legacy(_ s: UUID) -> StrengthCompletionEnvelope {
        StrengthCompletionEnvelope(sessionID: s, reason: nil, endedAt: deadline, inactivityDeadline: nil,
                                   completionID: nil, version: 1)
    }

    func testLegacyEndNeverAppliesToPhoneActiveSession() {
        let id = UUID()
        XCTAssertEqual(WatchSessionEndPolicy.decide(incoming: legacy(id), persisted: nil, activeSessionID: id, acceptedWatchRoute: nil), .rejectForeign)
        XCTAssertEqual(WatchSessionEndPolicy.decide(incoming: legacy(id), persisted: nil, activeSessionID: UUID(), acceptedWatchRoute: nil), .apply)
        XCTAssertEqual(WatchSessionEndPolicy.decide(incoming: legacy(id), persisted: nil, activeSessionID: nil, acceptedWatchRoute: nil), .apply)
    }

    func testValidInactivityEndsActivePhoneSession() {
        let id = UUID(); let r = route(id)
        XCTAssertEqual(WatchSessionEndPolicy.decide(incoming: inactivity(id, route: r), persisted: nil, activeSessionID: id, acceptedWatchRoute: r), .apply)
    }

    func testDuplicateCompletionIsAlreadyApplied() {
        let id = UUID(); let r = route(id); let cid = UUID()
        let rec = StrengthCompletionRecord(sessionID: id, completionID: cid, reason: .inactivity, endedAt: deadline)
        XCTAssertEqual(WatchSessionEndPolicy.decide(incoming: inactivity(id, id: cid, route: r), persisted: rec, activeSessionID: nil, acceptedWatchRoute: r), .alreadyApplied)
    }

    func testOlderCompletionCannotOverwriteUserFinish() {
        let id = UUID(); let r = route(id)
        let rec = StrengthCompletionRecord(sessionID: id, completionID: UUID(), reason: .user, endedAt: deadline.addingTimeInterval(60))
        XCTAssertEqual(WatchSessionEndPolicy.decide(incoming: inactivity(id, route: r), persisted: rec, activeSessionID: nil, acceptedWatchRoute: r), .rejectStale)
    }

    func testForeignOrMalformedInactivityRejected() {
        let id = UUID(); let r = route(id)
        // wrong route / no route
        XCTAssertEqual(WatchSessionEndPolicy.decide(incoming: inactivity(id, route: route(id)), persisted: nil, activeSessionID: id, acceptedWatchRoute: r), .rejectForeign)
        XCTAssertEqual(WatchSessionEndPolicy.decide(incoming: inactivity(id, route: nil), persisted: nil, activeSessionID: id, acceptedWatchRoute: nil), .rejectForeign)
        // mismatched deadline
        XCTAssertEqual(WatchSessionEndPolicy.decide(incoming: inactivity(id, dl: deadline.addingTimeInterval(5), route: r), persisted: nil, activeSessionID: id, acceptedWatchRoute: r), .rejectForeign)
        // route for a different session
        let other = route(UUID())
        XCTAssertEqual(WatchSessionEndPolicy.decide(incoming: inactivity(id, route: other), persisted: nil, activeSessionID: id, acceptedWatchRoute: other), .rejectForeign)
        // missing completion id
        let noID = StrengthCompletionEnvelope(sessionID: id, reason: .inactivity, endedAt: deadline, inactivityDeadline: deadline, completionID: nil, version: 2, route: r)
        XCTAssertEqual(WatchSessionEndPolicy.decide(incoming: noID, persisted: nil, activeSessionID: id, acceptedWatchRoute: r), .rejectForeign)
    }

    func testEnvelopeParsesPayloadAndDoesNotInferInactivity() {
        let id = UUID()
        let env = StrengthCompletionEnvelope(userInfo: ["session_id": id.uuidString, "ended_at": 5.0])
        XCTAssertNil(env.reason)
        XCTAssertFalse(env.isValidInactivity)
        let cid = UUID()
        let v2 = StrengthCompletionEnvelope(userInfo: [
            "session_id": id.uuidString, "ended_at": 5.0, "inactivity_deadline": 5.0,
            "completion_reason": "inactivity", "completion_id": cid.uuidString, "v": 2])
        XCTAssertTrue(v2.isValidInactivity)
        XCTAssertEqual(v2.completionID, cid)
    }
}
