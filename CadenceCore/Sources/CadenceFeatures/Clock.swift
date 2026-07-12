import Foundation

/// A tiny time seam so extracted models never call `Date()` directly. Following
/// the existing `WorkoutClock` / `PhaseCountdownClock` pattern in `CadenceCore`
/// (both take an injected `now:`), every `CadenceFeatures` model takes a `Clock`
/// so its time-dependent behavior is deterministic under `swift test`.
public struct Clock: Sendable {
    /// Returns the current instant. Injected so tests can pin it.
    public var now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date) {
        self.now = now
    }

    /// Wall-clock time — the production default.
    public static let live = Clock(now: { Date() })

    /// A clock pinned to a single instant.
    public static func fixed(_ date: Date) -> Clock {
        Clock(now: { date })
    }
}
