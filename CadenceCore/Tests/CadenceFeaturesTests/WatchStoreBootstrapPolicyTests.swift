import XCTest
@testable import CadenceFeatures

final class WatchStoreBootstrapPolicyTests: XCTestCase {
    func testFirstOpenSeedsAndIsReady() {
        var seeded = false
        let policy = WatchStoreBootstrapPolicy<Int>(createPersistent: { 1 }, createInMemory: { 2 }, quarantine: { nil }, seed: { _ in seeded = true })
        let result = policy.open()
        XCTAssertEqual(result.container, 1); XCTAssertEqual(result.state, .ready); XCTAssertTrue(seeded)
    }

    func testFailureQuarantinesThenRecovers() {
        var opens = 0
        let url = URL(fileURLWithPath: "/tmp/recovery")
        let policy = WatchStoreBootstrapPolicy<Int>(createPersistent: { opens += 1; if opens == 1 { throw NSError(domain: "test", code: 1) }; return 3 }, createInMemory: { 4 }, quarantine: { url }, seed: { _ in })
        let result = policy.open()
        XCTAssertEqual(result.container, 3); XCTAssertEqual(result.state, .recovered); XCTAssertEqual(result.quarantinedAt, url)
    }

    func testFailureTwiceFallsBackToMemoryWithoutClaimingRecovery() {
        let policy = WatchStoreBootstrapPolicy<Int>(createPersistent: { throw NSError(domain: "test", code: 1) }, createInMemory: { 9 }, quarantine: { throw NSError(domain: "move", code: 2) }, seed: { _ in })
        let result = policy.open()
        XCTAssertEqual(result.container, 9); XCTAssertEqual(result.state, .degraded); XCTAssertNil(result.quarantinedAt)
    }

    /// Pins the chosen semantic for when `quarantine()` itself throws: the
    /// policy goes straight to `.degraded` and does NOT attempt a second
    /// `createPersistent()` call, even if that second attempt would have
    /// succeeded. This is the behavior the real Watch app's bootstrap now
    /// inherits by delegating to this policy (it previously attempted a
    /// second persistent-store open in this exact situation); the simpler,
    /// already-tested policy semantic was chosen deliberately over
    /// preserving that extra retry.
    func testQuarantineFailureGoesStraightToDegradedWithoutRetryingCreatePersistent() {
        var opens = 0
        let policy = WatchStoreBootstrapPolicy<Int>(
            createPersistent: {
                opens += 1
                if opens == 1 { throw NSError(domain: "test", code: 1) }
                return 7 // would be returned if the policy ever retried
            },
            createInMemory: { 9 },
            quarantine: { throw NSError(domain: "move", code: 2) },
            seed: { _ in }
        )
        let result = policy.open()
        XCTAssertEqual(result.state, .degraded)
        XCTAssertEqual(result.container, 9)
        XCTAssertNil(result.quarantinedAt)
        XCTAssertEqual(opens, 1, "createPersistent must not be retried when quarantine() itself throws")
    }
}
