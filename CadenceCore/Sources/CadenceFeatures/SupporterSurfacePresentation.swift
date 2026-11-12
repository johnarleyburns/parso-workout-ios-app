import Foundation

public enum SupporterPurchaseResult: Equatable, Sendable {
    case idle, purchasing, succeeded
    case failed(message: String)
}

public enum SupporterPurchaseOutcome: Equatable, Sendable {
    case verifiedSuccess, cancelledOrPending
    case failure(message: String)
}

/// Reducer guarding the single Supporter purchase effect.
public struct SupporterPurchaseState: Equatable, Sendable {
    public private(set) var result: SupporterPurchaseResult = .idle
    private var lastSettled: SupporterPurchaseResult = .idle
    public init() {}

    /// Returns true only if a new purchase effect should launch.
    public mutating func begin() -> Bool {
        if result == .purchasing { return false }
        lastSettled = result
        result = .purchasing
        return true
    }

    public mutating func finish(_ outcome: SupporterPurchaseOutcome) {
        switch outcome {
        case .verifiedSuccess: result = .succeeded
        case .cancelledOrPending: result = lastSettled == .succeeded ? .succeeded : .idle
        case .failure(let m): result = .failed(message: m)
        }
    }
}

public struct SupporterSurfacePresentation: Equatable, Sendable {
    public let showsTodayBadge: Bool
    public let settingsTitle: String
    public let settingsDetail: String
    public let isPurchaseEnabled: Bool
    public let resultMessage: String?

    public init(isSupporter: Bool, result: SupporterPurchaseResult, productName: String) {
        showsTodayBadge = isSupporter
        if isSupporter {
            settingsTitle = String(localized: "Thanks for supporting \(productName)")
            settingsDetail = String(localized: "You have the Supporter badge")
        } else {
            settingsTitle = String(localized: "Contribute to Development")
            settingsDetail = String(localized: "A one-time, optional $9.99 — every feature is already free")
        }
        isPurchaseEnabled = result != .purchasing
        switch result {
        case .succeeded: resultMessage = String(localized: "Thank you for supporting \(productName)!")
        case .failed(let m): resultMessage = String(localized: "Purchase failed: \(m)")
        default: resultMessage = nil
        }
    }
}

public enum SupporterAccessibility {
    public static let section = "settings.section.support"
    public static let card = "settings.support"
    public static let badge = "home.supporterBadge"
    public static let cardCombinesTitleAndDetail = true
    public static let resultCombinedWithCard = false
}
