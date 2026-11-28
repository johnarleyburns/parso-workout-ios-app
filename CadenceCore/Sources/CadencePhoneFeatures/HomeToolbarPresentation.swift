import Foundation

/// One entry in the Home top-bar overflow menu. Strength and Cardio are no
/// longer tab-bar items; they open as their own surfaces from here.
public enum HomeMenuDestination: String, CaseIterable, Equatable, Sendable, Identifiable {
    case history
    case strengthWeek
    case cardioWeek
    case settings

    public var id: String { rawValue }
    public var accessibilityIdentifier: String { "home.menu.\(rawValue)" }
}

/// The tab bar after Strength and Cardio moved into the Home menu.
public enum RootTabItem: String, CaseIterable, Equatable, Sendable, Identifiable {
    case workout
    case progress
    case find

    public var id: String { rawValue }
}

public enum HomeToolbarPresentation {
    /// Trailing overflow, in shipping order.
    public static let menu: [HomeMenuDestination] = [.history, .strengthWeek, .cardioWeek, .settings]
    /// Visible tab-bar items, in shipping order.
    public static let tabs: [RootTabItem] = [.workout, .progress, .find]
}

public extension HomeHeaderPresentation {
    /// The Supporter badge is the only leading item; it is never tappable.
    var leadingItems: [TodayHeaderLeadingItem] {
        supporterBadge == nil ? [] : [.supporterBadge]
    }

    var menuItems: [HomeMenuDestination] { HomeToolbarPresentation.menu }
}

public enum TodayHeaderLeadingItem: Equatable, Sendable { case supporterBadge }
