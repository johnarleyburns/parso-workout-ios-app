import CadenceFeatures
import Foundation
import Observation
import CadenceCore

/// Rest-timer state (FR-1.5). Decrement logic is in `tick()` (not wall-clock) so
/// it is deterministic and unit-testable; the view drives `tick()` on a 1s timer.
///
/// Moved out of the app's `Features/Train/RestTimer.swift` (test-pyramid Phase 2)
/// so its tests run headlessly under `swift test`. The `RestTimerBar` view stays
/// in the app.
@Observable
public final class RestTimerModel {
    public private(set) var remaining: Int = 0
    public private(set) var total: Int = 0
    public private(set) var isRunning = false
    public private(set) var isPaused = false
    public private(set) var endsAt: Date?

    public init() {}

    public func start(seconds: Int) {
        total = seconds
        remaining = seconds
        isRunning = seconds > 0
        isPaused = false
        endsAt = isRunning ? Date().addingTimeInterval(TimeInterval(seconds)) : nil
    }

    public func tick() {
        guard isRunning, !isPaused else { return }
        remaining = max(0, remaining - 1)
        if remaining == 0 {
            isRunning = false
            isPaused = false
            endsAt = nil
        }
    }

    /// Freeze the countdown without ending it. `tick()` becomes a no-op until
    /// `resume()`, so warm-up and cool-down Pause behave like the workout's.
    public func pause() {
        guard isRunning else { return }
        isPaused = true
        endsAt = nil
    }

    public func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        endsAt = Date().addingTimeInterval(TimeInterval(remaining))
    }

    public func add(_ seconds: Int) {
        guard isRunning || remaining > 0 else { return }
        remaining += seconds
        total = max(total, remaining)
        if remaining > 0 {
            isRunning = true
            if !isPaused {
                endsAt = Date().addingTimeInterval(TimeInterval(remaining))
            }
        }
    }

    public func skip() {
        remaining = 0
        isRunning = false
        isPaused = false
        endsAt = nil
    }

    public var progress: Double {
        guard total > 0 else { return 0 }
        return Double(total - remaining) / Double(total)
    }
}
