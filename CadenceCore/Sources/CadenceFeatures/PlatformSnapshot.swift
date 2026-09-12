import Foundation

/// Small, privacy-preserving projection shared by the iPhone app and its
/// platform surfaces. It deliberately contains presentation text and stable
/// identifiers only; prescriptions and workout history remain in the app store.
public struct CadenceTodaySnapshot: Codable, Equatable, Sendable {
    public let dayKey: String
    public let planTitle: String
    public let sessionTitles: [String]
    public let readinessLabel: String?
    public let updatedAt: Date

    public init(dayKey: String, planTitle: String, sessionTitles: [String],
                readinessLabel: String? = nil, updatedAt: Date = Date()) {
        self.dayKey = dayKey
        self.planTitle = planTitle
        self.sessionTitles = sessionTitles
        self.readinessLabel = readinessLabel
        self.updatedAt = updatedAt
    }
}

/// App-group transport for widgets and other extensions. The fallback to
/// standard defaults keeps previews and unsigned local builds useful; the
/// shipped app and extension both use the shared suite when entitlements are
/// present.
public enum CadencePlatformSnapshotStore {
    public static let appGroupIdentifier = "group.guru.parso.ios-workout-app"
    public static let snapshotKey = "cadence.todaySnapshot.v1"

    public static func save(_ snapshot: CadenceTodaySnapshot,
                            defaults: UserDefaults? = nil) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        (defaults ?? sharedDefaults()).set(data, forKey: snapshotKey)
    }

    public static func load(defaults: UserDefaults? = nil) -> CadenceTodaySnapshot? {
        guard let data = (defaults ?? sharedDefaults()).data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(CadenceTodaySnapshot.self, from: data)
    }

    private static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}
