import Foundation

public enum RestAlertMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case inAppOnly
    case alarm

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .inAppOnly: return "In app only"
        case .alarm: return "Alarm (breaks through Silent)"
        }
    }
}
