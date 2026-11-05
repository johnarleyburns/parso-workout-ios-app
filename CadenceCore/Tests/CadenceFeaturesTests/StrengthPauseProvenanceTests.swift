import XCTest
@testable import CadenceFeatures

final class StrengthPauseProvenanceTests: XCTestCase {
    func testUserPauseResume() {
        var p = StrengthPauseProvenance()
        XCTAssertTrue(p.userPause(.userControl))
        XCTAssertEqual(p.origin, .userControl)
        XCTAssertEqual(p.healthKitTransition(to: .paused), .none)   // echo of our own pause
        XCTAssertEqual(p.origin, .userControl)
        XCTAssertEqual(p.healthKitTransition(to: .running), .none)  // platform can't resume a user pause
        XCTAssertEqual(p.origin, .userControl)
        p.userResume()
        XCTAssertNil(p.origin)
    }

    func testQuickTalkPause() {
        var p = StrengthPauseProvenance()
        XCTAssertTrue(p.userPause(.quickTalk))
        XCTAssertEqual(p.origin, .quickTalk)
        XCTAssertTrue(p.statusCopy!.contains("by you"))
    }

    func testNonUserOriginCannotBeSetAsUserPause() {
        var p = StrengthPauseProvenance()
        XCTAssertFalse(p.userPause(.healthKitExternal))
        XCTAssertFalse(p.userPause(.recovery))
        XCTAssertNil(p.origin)
    }

    func testExternalPausedIsRecordedOnceAndDistinctCopy() {
        var p = StrengthPauseProvenance()
        XCTAssertEqual(p.healthKitTransition(to: .paused), .pause)
        XCTAssertEqual(p.healthKitTransition(to: .paused), .none)   // repeated callback
        XCTAssertEqual(p.origin, .healthKitExternal)
        XCTAssertTrue(p.statusCopy!.contains("not by you"))
        XCTAssertEqual(p.healthKitTransition(to: .running), .resume)
        XCTAssertNil(p.origin)
        XCTAssertEqual(p.healthKitTransition(to: .running), .none)  // repeated
    }

    func testRecoveredPausedNeedsExplicitResume() {
        var p = StrengthPauseProvenance()
        p.recoveredPaused()
        XCTAssertEqual(p.origin, .recovery)
        XCTAssertTrue(p.statusCopy!.contains("Restored"))
        p.userResume()
        XCTAssertNil(p.origin)
    }

    func testTerminalClears() {
        var p = StrengthPauseProvenance()
        _ = p.userPause(.userControl)
        _ = p.healthKitTransition(to: .terminal)
        XCTAssertNil(p.origin)
        XCTAssertNil(p.statusCopy)
    }
}
