import XCTest
import CadenceFeatures

/// Launch-blockers Phase 1d: watch-relayed end messages never finalize the
/// phone's live workout.
final class WatchSessionEndPolicyTests: XCTestCase {

    func testDropsEndForPhoneActiveSession() {
        let id = UUID()
        XCTAssertFalse(WatchSessionEndPolicy.shouldApplyEnd(sessionID: id, phoneActiveID: id))
    }

    func testAppliesEndForOtherSessions() {
        XCTAssertTrue(WatchSessionEndPolicy.shouldApplyEnd(sessionID: UUID(), phoneActiveID: UUID()))
        XCTAssertTrue(WatchSessionEndPolicy.shouldApplyEnd(sessionID: UUID(), phoneActiveID: nil))
    }
}
