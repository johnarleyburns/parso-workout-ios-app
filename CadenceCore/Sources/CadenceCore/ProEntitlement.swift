import Foundation

/// How a user came to have Pro. Purely informational for UI copy; all sources
/// unlock the identical Coach entitlement.
public enum ProSource: String, Equatable, Sendable, Codable {
    case lifetime
    case subscription
    case trial
}

/// The single source of truth for whether the Coach is unlocked. The free app is
/// complete without Pro; Pro adds only the coaching layer (monetization plan §1).
public enum ProEntitlement: Equatable, Sendable, Codable {
    case free
    case pro(source: ProSource)

    public var isPro: Bool {
        if case .pro = self { return true }
        return false
    }

    public var source: ProSource? {
        if case .pro(let source) = self { return source }
        return nil
    }
}

/// StoreKit product identifiers. Reverse-DNS to match the repo's existing tip IDs
/// (`guru.parso.cladiron.tip.*`). Both subscriptions share one App Store
/// subscription group ("Cladiron Pro") at the same service level.
public enum ProProductID {
    public static let annual = "guru.parso.cladiron.pro.annual"
    public static let monthly = "guru.parso.cladiron.pro.monthly"
    public static let lifetime = "guru.parso.cladiron.pro.lifetime"

    public static let all: Set<String> = [annual, monthly, lifetime]
    public static let subscriptions: Set<String> = [annual, monthly]

    public static func isProProduct(_ id: String) -> Bool { all.contains(id) }
}

/// A StoreKit-agnostic snapshot of one owned transaction. Keeping the resolver
/// pure (no `import StoreKit`) means entitlement derivation is `swift test`-
/// verifiable on the Mac toolchain; the app maps `StoreKit.Transaction` into this.
public struct EntitlementRecord: Equatable, Sendable {
    public let productID: String
    public let purchaseDate: Date
    /// Subscriptions only; `nil` for the non-consumable lifetime.
    public let expirationDate: Date?
    /// Set when a transaction was refunded or revoked (e.g. Family Sharing removal).
    public let revocationDate: Date?
    /// True when the transaction redeemed the introductory free trial.
    public let isIntroductoryOffer: Bool
    /// True when this subscription was superseded by a crossgrade/upgrade.
    public let isUpgraded: Bool

    public init(
        productID: String,
        purchaseDate: Date,
        expirationDate: Date? = nil,
        revocationDate: Date? = nil,
        isIntroductoryOffer: Bool = false,
        isUpgraded: Bool = false
    ) {
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.isIntroductoryOffer = isIntroductoryOffer
        self.isUpgraded = isUpgraded
    }
}

/// Derives `ProEntitlement` from the set of currently-owned transactions. Pure and
/// deterministic so it is unit-tested exhaustively (lifetime, active sub, trial,
/// expired, revoked/refunded, upgraded, family-shared).
public enum EntitlementResolver {

    public static func resolve(records: [EntitlementRecord], now: Date = Date()) -> ProEntitlement {
        var best: ProEntitlement = .free
        for record in records {
            guard ProProductID.isProProduct(record.productID) else { continue }
            if record.revocationDate != nil { continue }
            if record.isUpgraded { continue }

            if record.productID == ProProductID.lifetime {
                return .pro(source: .lifetime) // lifetime always wins outright
            }

            // Subscription: must not be expired.
            if let expiration = record.expirationDate, expiration <= now { continue }
            let candidate: ProEntitlement = .pro(source: record.isIntroductoryOffer ? .trial : .subscription)
            best = preferred(best, candidate)
        }
        return best
    }

    /// lifetime > subscription > trial > free.
    private static func preferred(_ a: ProEntitlement, _ b: ProEntitlement) -> ProEntitlement {
        rank(a) >= rank(b) ? a : b
    }

    private static func rank(_ entitlement: ProEntitlement) -> Int {
        switch entitlement {
        case .free: return 0
        case .pro(.trial): return 1
        case .pro(.subscription): return 2
        case .pro(.lifetime): return 3
        }
    }
}

/// A cached entitlement + when it was recorded, persisted so a network blip at
/// cold launch never locks a paying user out mid-workout (monetization plan §4.3).
public struct CachedEntitlement: Equatable, Sendable, Codable {
    public let entitlement: ProEntitlement
    public let recordedAt: Date

    public init(entitlement: ProEntitlement, recordedAt: Date) {
        self.entitlement = entitlement
        self.recordedAt = recordedAt
    }
}

/// Offline-cache trust rules. Lifetime never goes stale; subscription/trial-sourced
/// Pro is trusted from cache for at most 30 days before StoreKit must reconfirm.
public enum EntitlementCachePolicy {
    public static let subscriptionStalenessCeiling: TimeInterval = 30 * 24 * 60 * 60

    public static func isUsable(_ cached: CachedEntitlement, now: Date = Date()) -> Bool {
        switch cached.entitlement {
        case .free:
            return true
        case .pro(.lifetime):
            return true
        case .pro(.subscription), .pro(.trial):
            let age = now.timeIntervalSince(cached.recordedAt)
            return age >= 0 && age <= subscriptionStalenessCeiling
        }
    }

    /// The entitlement to apply from cache when StoreKit is momentarily unavailable:
    /// the cached value if still trustworthy, otherwise `.free`.
    public static func effective(_ cached: CachedEntitlement?, now: Date = Date()) -> ProEntitlement {
        guard let cached, isUsable(cached, now: now) else { return .free }
        return cached.entitlement
    }
}
