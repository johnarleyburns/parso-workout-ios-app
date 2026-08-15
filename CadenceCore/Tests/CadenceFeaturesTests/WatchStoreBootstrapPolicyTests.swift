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
}
