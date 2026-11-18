import CadenceFeatures
import Foundation

public enum RestAlertMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case inAppOnly
    case alarm

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .inAppOnly: return {
            #if os(Linux)
            "In app only"
            #else
            String(localized: "In app only", bundle: FeatureLocalization.bundle)
            #endif
        }()
        case .alarm: return {
            #if os(Linux)
            "Alarm (breaks through Silent)"
            #else
            String(localized: "Alarm (breaks through Silent)", bundle: FeatureLocalization.bundle)
            #endif
        }()
        }
    }
}
