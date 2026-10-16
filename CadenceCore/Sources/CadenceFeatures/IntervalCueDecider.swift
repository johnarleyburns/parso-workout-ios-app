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
        case phaseTransition(IntervalPhaseKind)
        /// Final 3…1 seconds before a work interval starts; `3` is the cue to say "Get ready".
        case getReady(Int)
    }

    private var lastWarnedPhase: Int?
    private var lastTickSecond = -1
    private var lastPhaseID: Int?
    private var lastReadySecond = -1

    public init() {}

    /// Re-arm timing trackers (called after a phase skip so warnings/ticks fire
    /// for the new phase). Phase tracking is deliberately preserved so the next
    /// tick can still detect a real transition.
    public mutating func reset() {
        lastWarnedPhase = nil
        lastTickSecond = -1
        lastReadySecond = -1
    }

    /// The cues to fire for the current tick, mutating internal guards so each cue
    /// fires at most once per boundary.
    public mutating func cues(phaseKind: IntervalPhaseKind?,
                              currentPhaseID: Int?,
                              phaseRemaining: TimeInterval,
                              phaseDuration: TimeInterval = 180,
                              nextPhaseKind: IntervalPhaseKind? = nil,
                              isPaused: Bool,
                              isComplete: Bool) -> [Cue] {
        guard !isPaused, !isComplete else { return [] }

        var out: [Cue] = []
        let secs = Int(phaseRemaining.rounded(.up))

        if let currentPhaseID {
            if let lastPhaseID, currentPhaseID != lastPhaseID, let phaseKind {
                out.append(.phaseTransition(phaseKind))
                lastTickSecond = -1
            }
            lastPhaseID = currentPhaseID
        }

        // Duration-aware warning (once per work phase). Rounded whole seconds
        // keep cue timing aligned with the visible countdown.
        let warningSecond = Int(IntervalSignal.warningDuration(forWorkDuration: phaseDuration))
        if phaseKind == .work, secs == warningSecond, currentPhaseID != lastWarnedPhase {
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

        // "Get ready" countdown on the final 3 seconds before a work interval.
        if phaseKind != .work, nextPhaseKind == .work, (1...3).contains(secs) {
            if secs != lastReadySecond {
                out.append(.getReady(secs))
                lastReadySecond = secs
            }
        } else if secs > 3 {
            lastReadySecond = -1
        }

        return out
    }
}
