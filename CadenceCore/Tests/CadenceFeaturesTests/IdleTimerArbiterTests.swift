import XCTest
import CadenceFeatures

/// Launch-blockers Phase 1c: reference-counted keep-awake holders.
final class IdleTimerArbiterTests: XCTestCase {

    func testUnionOfHolders() {
        let arbiter = IdleTimerArbiter()
        var applied: [Bool] = []
        arbiter.apply = { applied.append($0) }

        arbiter.acquire("session")
        arbiter.acquire("hrGate")
        XCTAssertTrue(arbiter.keepAwake)
        arbiter.release("session")
        XCTAssertTrue(arbiter.keepAwake, "one holder remains → still awake")
        XCTAssertEqual(applied, [true, true, true])
    }

    func testLastReleaseRestores() {
        let arbiter = IdleTimerArbiter()
        var last: Bool?
        arbiter.apply = { last = $0 }
        arbiter.acquire("a")
        arbiter.acquire("b")
        arbiter.release("a")
        arbiter.release("b")
        XCTAssertFalse(arbiter.keepAwake)
        XCTAssertEqual(last, false)
    }

    func testReassertMatchesHolders() {
        let arbiter = IdleTimerArbiter()
        arbiter.acquire("session")
        // The OS may have reset the idle timer while backgrounded; reassert
        // pushes the current union again on foregrounding.
        var last: Bool?
        arbiter.apply = { last = $0 }
        arbiter.reassert()
        XCTAssertEqual(last, true)

        arbiter.release("session")
        last = nil
        arbiter.reassert()
        XCTAssertEqual(last, false)
    }

    func testDuplicateAcquireIsIdempotentPerToken() {
        let arbiter = IdleTimerArbiter()
        arbiter.acquire("x")
        arbiter.acquire("x")
        arbiter.release("x")
        XCTAssertFalse(arbiter.keepAwake)
    }
}
