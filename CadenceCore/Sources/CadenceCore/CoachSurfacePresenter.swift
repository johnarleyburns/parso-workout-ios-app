import Foundation

/// The coach's presence on Home (coach-surface-design.md §2, as amended
/// 2026-07-03). Drives how prominently the coach appears to a free user without
/// ever suppressing the *insight* itself — only the introducing card and the
/// "Unlock the Coach" CTA are paced.
public enum CoachSurfaceState: String, Sendable, Equatable {
    /// New/updated user (first N Home sessions) or after a protocol-pack release:
    /// full preview card at the top of Home.
    case introducing
    /// Default steady state for a free user with nothing new to observe: a compact
    /// directory row placed below the user's own data.
    case ambient
    /// Free user with a live coach observation available: the compact row expands
    /// to show the insight.
    case insight
    /// User chose "Hide Coach offers": no Home presence (still reachable via the
    /// Programs tab and Settings).
    case hidden
    /// Entitled via free trial: the full coaching card is the functional surface.
    case trial
    /// Entitled (subscription/lifetime): the full coaching card.
    case pro

    /// Whether this state shows the full functional coaching card (earned placement).
    public var showsCoachingCard: Bool { self == .trial || self == .pro }
    /// Whether this state shows the compact `CoachRow` on Home.
    public var showsCompactRow: Bool { self == .ambient || self == .insight }
}

/// Pure resolver for the Home coach surface. Deterministic and `swift test`-verifiable.
public enum CoachSurfacePresenter {
    /// Number of `introducing` Home impressions before demoting to the ambient row.
    public static let introImpressionCap = 3

    /// Resolve the current surface state.
    ///
    /// - Parameters:
    ///   - entitlement: the Pro entitlement (overrides all presentation states).
    ///   - hidden: user opted out of coach offers.
    ///   - introImpressions: how many times the introducing card has been shown.
    ///   - hasInsight: whether a live coach observation is available right now.
    ///   - protocolPackPending: a new KB/protocol pack shipped and hasn't been seen.
    public static func state(entitlement: ProEntitlement,
                             hidden: Bool,
                             introImpressions: Int,
                             hasInsight: Bool,
                             protocolPackPending: Bool = false) -> CoachSurfaceState {
        switch entitlement {
        case .pro(.trial):
            return .trial
        case .pro:
            return .pro
        case .free:
            break
        }

        if hidden { return .hidden }
        if protocolPackPending || introImpressions < introImpressionCap { return .introducing }
        return hasInsight ? .insight : .ambient
    }
}
