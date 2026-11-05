import Foundation

/// Why a Watch strength session is paused. Only explicit user actions set
/// `.userControl` / `.quickTalk`; a HealthKit `.paused` transition nobody asked
/// for is `.healthKitExternal`. App lifecycle, wrist wake, HR, and
/// WatchConnectivity events never produce a pause or a resume.
public enum WatchPauseOrigin: String, Codable, Sendable, Equatable {
    case userControl, quickTalk, healthKitExternal, recovery

    public var isUserInitiated: Bool { self == .userControl || self == .quickTalk }
}

/// Pure pause-provenance state machine (headless-testable).
public struct StrengthPauseProvenance: Equatable, Sendable {
    public private(set) var origin: WatchPauseOrigin?
    public private(set) var since: Date?

    public init(origin: WatchPauseOrigin? = nil, since: Date? = nil) {
        self.origin = origin
        self.since = since
    }

    /// Explicit user pause. Returns true if a new pause began.
    @discardableResult
    public mutating func userPause(_ origin: WatchPauseOrigin, now: Date = Date()) -> Bool {
        guard origin.isUserInitiated, self.origin == nil else { return false }
        self.origin = origin
        since = now
        return true
    }

    /// Explicit user resume. Clears provenance.
    public mutating func userResume() {
        origin = nil
        since = nil
    }

    /// HealthKit delegate callback. Returns whether the elapsed tracker
    /// should start (`.pause`) or stop (`.resume`) pause accounting.
    public enum TrackerAction: Equatable, Sendable { case none, pause, resume }

    public mutating func healthKitTransition(to state: HKStateKind, now: Date = Date()) -> TrackerAction {
        switch state {
        case .paused:
            if origin != nil { return .none } // already explained; repeated callback
            origin = .healthKitExternal
            since = now
            return .pause
        case .running:
            // Only a platform-originated pause is cleared by the platform;
            // a user pause is cleared by an explicit user resume only.
            guard origin == .healthKitExternal || origin == .recovery else { return .none }
            origin = nil
            since = nil
            return .resume
        case .terminal:
            let had = origin != nil
            origin = nil
            since = nil
            return had ? .resume : .none
        case .other:
            return .none
        }
    }

    /// Recovered a paused session from a prior launch with no known cause.
    public mutating func recoveredPaused(now: Date = Date()) {
        guard origin == nil else { return }
        origin = .recovery
        since = now
    }

    public mutating func clear() { origin = nil; since = nil }

    public enum HKStateKind: Equatable, Sendable { case running, paused, terminal, other }

    /// Pause-page copy; differentiates user versus external/recovered pauses.
    public var statusCopy: String? {
        switch origin {
        case nil: return nil
        case .userControl, .quickTalk: return "Paused by you. Tap Resume to continue."
        case .healthKitExternal: return "Paused by watchOS, not by you. Tap Resume to continue."
        case .recovery: return "Restored as paused after a restart. Tap Resume to continue."
        }
    }
}
