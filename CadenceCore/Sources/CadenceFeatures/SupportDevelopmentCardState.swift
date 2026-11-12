import Foundation

/// Pure presentation model for the first-row "Support Cladiron" Settings card.
/// The view localizes copy from `kind`; no purchase/business decisions live in the view.
public struct SupportDevelopmentCardState: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case purchaseable
        case purchasing
        case unavailable
        case supporter
    }

    public let kind: Kind
    /// Localized product display price (empty unless a product is available).
    public let priceText: String
    public let iconName: String

    public var isEnabled: Bool { kind == .purchaseable }
    public var canPurchase: Bool { kind == .purchaseable }
    public var showsProgress: Bool { kind == .purchasing }

    public static func make(productPrice: String?, isSupporter: Bool, purchasingID: String?) -> Self {
        if isSupporter { return .init(kind: .supporter, priceText: productPrice ?? "", iconName: "heart.fill") }
        if purchasingID != nil { return .init(kind: .purchasing, priceText: productPrice ?? "", iconName: "heart.fill") }
        guard let productPrice else { return .init(kind: .unavailable, priceText: "", iconName: "heart.fill") }
        return .init(kind: .purchaseable, priceText: productPrice, iconName: "heart.fill")
    }
}

/// Ordered Settings section identifiers; support is always first.
public enum SettingsSectionOrder {
    public static let supportCardCount = 1
    public static let identifiers: [String] = [
        "settings.section.support",
        "settings.section.preferences",
        "settings.section.health",
        "settings.section.watch",
        "settings.section.coach",
        "settings.section.exercises",
        "settings.section.data",
        "settings.section.transparency",
        "settings.section.cloudKit",
        "settings.section.about",
    ]
}
