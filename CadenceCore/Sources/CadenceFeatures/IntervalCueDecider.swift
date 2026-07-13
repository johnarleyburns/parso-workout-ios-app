import Foundation
import CadenceCore

/// The pure cue-timing state machine extracted from the app's `IntervalCueScheduler`
/// (test-pyramid Phase 2). Given the runner's current phase state each tick, it
/// decides which audio/haptic cues should fire — the 30-second work warning (once
/// per work phase) and the final 3-second countdown ticks — tracking the same
/// `lastWarnedPhase` / `lastTickSecond` guards. The app wrapper keeps the `Timer`
/// and the AVFoundation cue player; only this decision logic is unit-tested.
public struct IntervalCueDecider {
    public enum Cue: Equatable {
        case warning
        case countdownTick
    }

    private var lastWarnedPhase: Int?
    private var lastTickSecond = -1

    public init() {}

    /// Re-arm trackers (called after a phase skip so warnings/ticks fire for the
    /// new phase).
    public mutating func reset() {
        lastWarnedPhase = nil
        lastTickSecond = -1
    }

    /// The cues to fire for the current tick, mutating internal guards so each cue
    /// fires at most once per boundary.
    public mutating func cues(phaseKind: IntervalPhaseKind?,
                              currentPhaseID: Int?,
                              phaseRemaining: TimeInterval,
                              isPaused: Bool,
                              isComplete: Bool) -> [Cue] {
        guard !isPaused, !isComplete else { return [] }

        var out: [Cue] = []
        let secs = Int(phaseRemaining.rounded(.up))

        // 30-second warning (once per work phase)
        if phaseKind == .work, secs == 30, currentPhaseID != lastWarnedPhase {
            out.append(.warning)
            lastWarnedPhase = currentPhaseID
        }

        // Countdown ticks on the final 3 whole seconds of a work phase
        if phaseKind == .work, (1...3).contains(secs), secs != lastTickSecond {
            out.append(.countdownTick)
            lastTickSecond = secs
        } else if secs > 3 {
            lastTickSecond = -1
        }

        return out
    }
}
