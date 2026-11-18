import CadenceFeatures
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
            settingsTitle = {
                #if os(Linux)
                "Thanks for supporting \(productName)"
                #else
                String(localized: "Thanks for supporting \(productName)")
                #endif
            }()
            settingsDetail = {
                #if os(Linux)
                "You have the Supporter badge"
                #else
                String(localized: "You have the Supporter badge")
                #endif
            }()
        } else {
            settingsTitle = {
                #if os(Linux)
                "Contribute to Development"
                #else
                String(localized: "Contribute to Development")
                #endif
            }()
            settingsDetail = {
                #if os(Linux)
                "A one-time, optional $9.99 — every feature is already free"
                #else
                String(localized: "A one-time, optional $9.99 — every feature is already free")
                #endif
            }()
        }
        isPurchaseEnabled = result != .purchasing
        switch result {
        case .succeeded: resultMessage = {
            #if os(Linux)
            "Thank you for supporting \(productName)!"
            #else
            String(localized: "Thank you for supporting \(productName)!")
            #endif
        }()
        case .failed(let m): resultMessage = {
            #if os(Linux)
            "Purchase failed: \(m)"
            #else
            String(localized: "Purchase failed: \(m)")
            #endif
        }()
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
