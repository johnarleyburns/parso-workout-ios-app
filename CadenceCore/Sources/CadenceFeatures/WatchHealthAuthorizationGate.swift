import Foundation

/// Decides when the Watch shows its first-screen "Heart Rate Access" boundary.
///
/// It used to be a sticky UserDefaults flag: once the user tapped Continue (or
/// "Continue without heart rate") on any build, the screen never came back,
/// even while HealthKit had still never been asked. HealthKit is the source of
/// truth instead: `HKHealthStore.statusForAuthorizationRequest` reports
/// `.shouldRequest` exactly when the system sheet has not been answered for the
/// types the app needs (including newly added types), and `.unnecessary`
/// once it has, whichever way the user chose. HealthKit never reveals whether
/// read access was granted, so this is the most the app can honestly know.
///
/// - `.shouldRequest`: show the boundary first, on every launch, until the
///   system sheet is answered. "Continue without heart rate" skips it for the
///   current launch only.
/// - `.unnecessary`: never show it, unless the user is mid-flow on it right now
///   (the sheet just returned and the screen is waiting for Continue).
/// - Unknown or error: keep whatever is showing.
public enum WatchHealthAuthorizationGate {
    public enum RequestStatus: Equatable, Sendable {
        case shouldRequest
        case unnecessary
        case unknown
    }

    /// Legacy "the user finished the first-launch screen" flag.
    public static let resolvedKey = "watch.initialHealthAuthorizationResolved"
    /// HealthKit's last answer, so the next cold launch can render the right
    /// first frame before HealthKit answers again.
    public static let lastKnownNeedsRequestKey = "watch.healthAuthorization.lastKnownNeedsRequest"

    /// The first frame, before HealthKit has answered this launch.
    public static func initialGateActive(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: lastKnownNeedsRequestKey) != nil {
            return defaults.bool(forKey: lastKnownNeedsRequestKey)
        }
        return !defaults.bool(forKey: resolvedKey)
    }

    /// The gate once HealthKit has answered.
    public static func gateActive(current: Bool,
                                  status: RequestStatus,
                                  dismissedThisLaunch: Bool,
                                  flowStarted: Bool) -> Bool {
        switch status {
        case .shouldRequest:
            return !dismissedThisLaunch
        case .unnecessary:
            return flowStarted ? current : false
        case .unknown:
            return current
        }
    }

    /// Remembers HealthKit's answer for the next launch's first frame.
    public static func record(_ status: RequestStatus, defaults: UserDefaults = .standard) {
        switch status {
        case .shouldRequest:
            defaults.set(true, forKey: lastKnownNeedsRequestKey)
        case .unnecessary:
            defaults.set(false, forKey: lastKnownNeedsRequestKey)
        case .unknown:
            break
        }
    }
}
