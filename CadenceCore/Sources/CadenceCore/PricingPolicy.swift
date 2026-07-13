import Foundation

/// Pricing constants and the founding-price predicate.
///
/// Pure, so the paywall's business logic is `swift test`-verifiable rather than
/// stranded at a SwiftUI call site. (A hardcoded price literal in a `View` is the
/// same class of untestable mistake this package exists to prevent.)
public enum PricingPolicy {
    /// The lifetime product's full (non-promotional) price.
    public static let lifetimeFullPrice = Decimal(149.99)

    /// True while the lifetime product is still below its full price — i.e. the
    /// launch "founding price" window is open.
    public static func isFoundingPrice(_ price: Decimal) -> Bool {
        price < lifetimeFullPrice
    }
}
