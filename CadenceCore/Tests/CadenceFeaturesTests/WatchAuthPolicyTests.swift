import XCTest
@testable import CadenceFeatures

final class WatchAuthPolicyTests: XCTestCase {

    func testAuthorized_allowsStart() {
        let d = WatchAuthPolicy.evaluate(shareStatus: .authorized, hrSampleSeen: false, sessionIsActive: false)
        XCTAssertTrue(d.canStart)
        XCTAssertFalse(d.showDeniedWarning)
        XCTAssertFalse(d.hrHint)
    }

    func testNotDetermined_deniesStart() {
        let d = WatchAuthPolicy.evaluate(shareStatus: .notDetermined, hrSampleSeen: false, sessionIsActive: false)
        XCTAssertFalse(d.canStart)
        XCTAssertFalse(d.showDeniedWarning)
        XCTAssertFalse(d.hrHint)
    }

    func testDenied_deniesStart_showsWarning() {
        let d = WatchAuthPolicy.evaluate(shareStatus: .denied, hrSampleSeen: false, sessionIsActive: false)
        XCTAssertFalse(d.canStart)
        XCTAssertTrue(d.showDeniedWarning)
        XCTAssertFalse(d.hrHint)
    }

    func testHrHint_whenActiveNoSamples() {
        let d = WatchAuthPolicy.evaluate(shareStatus: .authorized, hrSampleSeen: false, sessionIsActive: true)
        XCTAssertTrue(d.canStart)
        XCTAssertTrue(d.hrHint)
    }

    func testNoHrHint_whenSamplesSeen() {
        let d = WatchAuthPolicy.evaluate(shareStatus: .authorized, hrSampleSeen: true, sessionIsActive: true)
        XCTAssertTrue(d.canStart)
        XCTAssertFalse(d.hrHint)
    }

    func testNoHrHint_whenNotActive() {
        let d = WatchAuthPolicy.evaluate(shareStatus: .authorized, hrSampleSeen: false, sessionIsActive: false)
        XCTAssertFalse(d.hrHint)
    }
}
