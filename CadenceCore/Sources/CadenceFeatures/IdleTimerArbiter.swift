import Foundation
import Observation

/// Reference-counted keep-awake arbiter (launch-blockers plan, Phase 1c).
///
/// Any surface that must keep the screen on (live session, HR gate, get-ready
/// countdown, warm-up/cool-down overlay, minimized-but-running workout)
/// acquires a token; the union decides whether the system idle timer should be
/// disabled. The app layer supplies `apply` (mapping the union onto
/// `UIApplication.isIdleTimerDisabled`) and calls `reassert()` on foregrounding
/// so the OS state always matches the holder set.
@Observable
public final class IdleTimerArbiter {
    public private(set) var holders: Set<String> = []

    /// Maps the current union onto the platform idle timer. Called on every
    /// acquire/release/reassert with the current `keepAwake` value.
    @ObservationIgnored public var apply: ((Bool) -> Void)?

    public init() {}

    /// True while at least one surface holds a token.
    public var keepAwake: Bool { !holders.isEmpty }

    public func acquire(_ token: String) {
        holders.insert(token)
        apply?(keepAwake)
    }

    public func release(_ token: String) {
        holders.remove(token)
        apply?(keepAwake)
    }

    /// Re-pushes the current union to the platform (scenePhase == .active).
    public func reassert() {
        apply?(keepAwake)
    }
}
