import XCTest
@testable import CadenceCore

final class ContributionTransactionPolicyTests: XCTestCase {
    private let tip = "guru.parso.cladiron.tip.generous"

    func testTipGrants() {
        XCTAssertTrue(ContributionTransactionPolicy.grantsSupporterStatus(productID: tip, contributionProductIDs: [tip]))
    }
    func testUnrelatedDoesNotGrant() {
        XCTAssertFalse(ContributionTransactionPolicy.grantsSupporterStatus(productID: "other.product", contributionProductIDs: [tip]))
    }
    func testEmptyListDoesNotGrant() {
        XCTAssertFalse(ContributionTransactionPolicy.grantsSupporterStatus(productID: tip, contributionProductIDs: []))
    }
    func testMultipleConfiguredIDsGrant() {
        let ids = [tip, "guru.parso.cladiron.tip.second"]
        for id in ids {
            XCTAssertTrue(ContributionTransactionPolicy.grantsSupporterStatus(productID: id, contributionProductIDs: ids))
        }
    }
    func testUnrelatedVerifiedEventLeavesSupporterFalse() {
        var tracker = SupporterStatusTracker(contributionProductIDs: [tip])
        XCTAssertFalse(tracker.handleVerifiedTransaction(productID: "other.product"))
        XCTAssertFalse(tracker.isSupporter)
        XCTAssertTrue(tracker.handleVerifiedTransaction(productID: tip))
        XCTAssertTrue(tracker.isSupporter)
    }
}
