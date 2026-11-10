import Foundation

/// Pure policy: only transactions for configured contribution products may
/// grant Supporter status. Unrelated purchases never do.
public enum ContributionTransactionPolicy {
    public static func grantsSupporterStatus(
        productID: String,
        contributionProductIDs: [String]
    ) -> Bool {
        contributionProductIDs.contains(productID)
    }
}

/// Testable event-handling seam for verified transaction events (by product ID).
public struct SupporterStatusTracker: Sendable, Equatable {
    public private(set) var isSupporter: Bool
    public let contributionProductIDs: [String]

    public init(contributionProductIDs: [String], isSupporter: Bool = false) {
        self.contributionProductIDs = contributionProductIDs
        self.isSupporter = isSupporter
    }

    /// Returns true when the event granted (or retained) Supporter status.
    @discardableResult
    public mutating func handleVerifiedTransaction(productID: String) -> Bool {
        if ContributionTransactionPolicy.grantsSupporterStatus(
            productID: productID, contributionProductIDs: contributionProductIDs) {
            isSupporter = true
            return true
        }
        return false
    }
}
