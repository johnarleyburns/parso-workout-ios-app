import Foundation

/// The account precondition for the private SwiftData↔CloudKit store. This is
/// deliberately framework-free so account-state presentation and tests do not
/// need a live CloudKit container.
public enum CloudKitAccountAvailability: String, Codable, Equatable, Sendable {
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable

    public var displayName: String {
        switch self {
        case .checking: return "Checking…"
        case .available: return "Available"
        case .noAccount: return "Sign in to iCloud"
        case .restricted: return "Restricted"
        case .temporarilyUnavailable: return "Unavailable"
        }
    }

    public var canSync: Bool { self == .available }
}

public enum CloudKitAccountGate {
    /// Maps `CKAccountStatus.rawValue` without making CadenceCore depend on
    /// CloudKit. Values are stable in Apple's public enum: available=1,
    /// couldNotDetermine=2, restricted=3, noAccount=4.
    public static func availability(for rawStatus: Int) -> CloudKitAccountAvailability {
        switch rawStatus {
        case 1: return .available
        case 3: return .restricted
        case 4: return .noAccount
        default: return .temporarilyUnavailable
        }
    }
}
