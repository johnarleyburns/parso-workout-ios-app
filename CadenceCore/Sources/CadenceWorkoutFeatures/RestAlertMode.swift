import CadenceFeatures
import Foundation

public enum RestAlertMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case inAppOnly
    case alarm

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .inAppOnly: return String(localized: "In app only", bundle: FeatureLocalization.bundle)
        case .alarm: return String(localized: "Alarm (breaks through Silent)", bundle: FeatureLocalization.bundle)
        }
    }
}
