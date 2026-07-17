import SwiftUI
import WatchKit
import CadenceCore
import CadenceFeatures

/// Plays haptic cues on watchOS driven by the pure `IntervalCueDecider` logic.
/// Boxing uses a stronger pattern; HIIT uses soft taps.
@Observable
final class WatchIntervalHaptics {
    private let device = WKInterfaceDevice.current()
    private var decider = IntervalCueDecider()
    private var lastPhaseID: Int? = nil

    func tick(runner: IntervalRunner) {
        guard !runner.isComplete else {
            if lastPhaseID != nil { device.play(.success); lastPhaseID = nil }
            return
        }

        let cues = decider.cues(
            phaseKind: runner.phaseKind,
            currentPhaseID: runner.currentPhaseID,
            phaseRemaining: runner.phaseRemaining,
            isPaused: runner.isPaused,
            isComplete: runner.isComplete
        )

        for cue in cues {
            switch cue {
            case .warning:
                device.play(.directionUp)
            case .countdownTick:
                device.play(.click)
            }
        }

        // Phase transition haptic
        if let current = runner.currentPhaseID, current != lastPhaseID {
            lastPhaseID = current
            guard let kind = runner.phaseKind else { return }
            switch kind {
            case .work: device.play(.success)
            case .rest: device.play(.directionDown)
            case .warmup: device.play(.directionUp)
            case .cooldown: device.play(.directionDown)
            }
            decider.reset()
        }
    }

    func stop() {
        lastPhaseID = nil
        decider.reset()
    }
}
