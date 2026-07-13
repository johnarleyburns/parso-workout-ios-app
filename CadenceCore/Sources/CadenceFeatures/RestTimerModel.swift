import Foundation
import Observation
import CadenceCore

/// Rest-timer state (FR-1.5). Decrement logic is in `tick()` (not wall-clock) so
/// it is deterministic and unit-testable; the view drives `tick()` on a 1s timer.
///
/// Moved out of the app's `Features/Train/RestTimer.swift` (test-pyramid Phase 2)
/// so its 6 tests run headlessly under `swift test`. The `RestTimerBar` view stays
/// in the app.
@Observable
public final class RestTimerModel {
    public private(set) var remaining: Int = 0
    public private(set) var total: Int = 0
    public private(set) var isRunning = false

    public init() {}

    public func start(seconds: Int) {
        total = seconds
        remaining = seconds
        isRunning = seconds > 0
    }

    public func tick() {
        guard isRunning else { return }
        remaining = max(0, remaining - 1)
        if remaining == 0 { isRunning = false }
    }

    public func add(_ seconds: Int) {
        guard isRunning || remaining > 0 else { return }
        remaining += seconds
        total = max(total, remaining)
        if remaining > 0 { isRunning = true }
    }

    public func skip() {
        remaining = 0
        isRunning = false
    }

    public var progress: Double {
        guard total > 0 else { return 0 }
        return Double(total - remaining) / Double(total)
    }
}
