import Foundation

/// Foundation-only seams for the single one-time Supporter purchase. StoreKit and
/// `UserDefaults` live in the iOS app target; this file holds only value policy.
public enum SupportProductConfiguration {
    /// The one source of truth for the Supporter consumable.
    public static let productID = "guru.parso.workout.support.dev"
    /// The persisted device-local Supporter flag (Workout-scoped).
    public static let supporterDefaultsKey = "workout.isSupporter"
    /// Legacy key, read only to migrate an existing true value once.
    public static let legacySupporterDefaultsKey = "cladiron.everContributed"
}

/// Pure policy: only a verified transaction for the configured product marks Supporter.
public enum ContributionTransactionPolicy {
    public enum Effect: Equatable, Sendable {
        case markSupporter
        case finish
    }

    public enum PurchaseOutcome: Equatable, Sendable {
        case verified(productID: String)
        case unverified
        case cancelled
        case pending
        case failed
    }

    public static func grantsSupporterStatus(productID: String) -> Bool {
        productID == SupportProductConfiguration.productID
    }

    /// Effects of a verified/unverified transaction observed on the update stream.
    public static func effects(forUpdateVerified verified: Bool, productID: String) -> [Effect] {
        guard verified else { return [] }
        return grantsSupporterStatus(productID: productID) ? [.markSupporter, .finish] : [.finish]
    }

    /// Effects of a `Product.purchase()` outcome.
    public static func effects(for outcome: PurchaseOutcome) -> [Effect] {
        switch outcome {
        case .verified(let id): return effects(forUpdateVerified: true, productID: id)
        case .unverified, .cancelled, .pending, .failed: return []
        }
    }

    /// Whether the purchase call should report success to the caller.
    public static func isSuccess(_ outcome: PurchaseOutcome) -> Bool {
        effects(for: outcome).contains(.markSupporter)
    }

    /// One-time migration: legacy true → new true; never regresses true.
    public static func migratedSupporter(current: Bool, legacy: Bool) -> Bool {
        current || legacy
    }
}

/// Dedupes finishing when the purchase result and update stream observe the same transaction.
public struct TransactionFinishLedger: Sendable, Equatable {
    public private(set) var finishedIDs: Set<UInt64> = []
    public private(set) var isSupporter: Bool

    public init(isSupporter: Bool = false) { self.isSupporter = isSupporter }

    /// Applies an observation; returns the effects to perform (finish at most once per id).
    public mutating func observe(
        transactionID: UInt64, productID: String, verified: Bool
    ) -> [ContributionTransactionPolicy.Effect] {
        var out = ContributionTransactionPolicy.effects(forUpdateVerified: verified, productID: productID)
        if out.contains(.markSupporter) { isSupporter = true }
        if out.contains(.finish) {
            if !finishedIDs.insert(transactionID).inserted { out.removeAll { $0 == .finish } }
        }
        return out
    }
}

/// Singular product presentation: no list, deterministic unavailable state.
public enum SupportProductPresentation: Equatable, Sendable {
    case unavailable
    case available(price: String)

    public static func make(displayPrice: String?) -> Self {
        guard let displayPrice else { return .unavailable }
        return .available(price: displayPrice)
    }
}
