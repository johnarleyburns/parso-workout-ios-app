import Foundation

/// Governs how often the prominent "Unlock the Coach" call-to-action may surface
/// on the free-tier Coach card.
///
/// Design intent (coach-surface-design.md, 2026-07-03 amendment): the coach's
/// *insight* (its observation about the user's training) is shown continuously —
/// it is never rate-limited, because seeing real, live value is what earns the
/// subscription. The *prescription* (what the coach would do about it) stays
/// locked. The ONLY thing this policy throttles is the big green upsell CTA, so a
/// free user's Home never reads like a running ad. A discreet, always-available
/// tap target on the locked prescription still lets a motivated user convert
/// between billboard impressions.
///
/// Pure and deterministic so it is `swift test`-verifiable on the Mac toolchain.
public enum CoachUpsellPolicy {
    /// Minimum time between two prominent "Unlock the Coach" CTA impressions.
    public static let minimumInterval: TimeInterval = 14 * 24 * 60 * 60

    /// Whether the prominent "Unlock the Coach" CTA should be shown right now.
    ///
    /// - Pro users never see it (they already have the coach).
    /// - It surfaces the first time (no prior impression), then stays hidden until
    ///   `minimumInterval` has elapsed since the last impression.
    ///
    /// - Parameters:
    ///   - isPro: whether the user already has the Coach entitlement.
    ///   - lastShown: when the CTA was last displayed, or `nil` if never.
    ///   - now: the current time (injectable for tests).
    public static func shouldShowCTA(isPro: Bool,
                                     lastShown: Date?,
                                     now: Date = Date()) -> Bool {
        guard !isPro else { return false }
        guard let lastShown else { return true }
        return now.timeIntervalSince(lastShown) >= minimumInterval
    }
}
