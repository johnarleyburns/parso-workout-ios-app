import SwiftUI
import WatchKit
import CadenceCore
import CadenceFeatures

/// Plays haptic cues on watchOS driven by the pure `IntervalCueDecider` logic.
/// Boxing uses a stronger pattern; HIIT uses soft taps.
@Observable
final class WatchIntervalHaptics {
    private let device = WKInterfaceDevice.current()
    private let audio = WatchIntervalCuePlayer()
    private var decider = IntervalCueDecider()
    private var lastPhaseID: Int? = nil

    func tick(runner: IntervalRunner, soundsEnabled: Bool, isBoxing: Bool) {
        guard !runner.isComplete else {
            if lastPhaseID != nil {
                playHapticSequence(.success, count: 3)
                audio.phaseTransition(soundsEnabled: soundsEnabled, isBoxing: isBoxing)
                lastPhaseID = nil
            }
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
                audio.warning(soundsEnabled: soundsEnabled, isBoxing: isBoxing)
            case .countdownTick:
                device.play(.click)
            }
        }

        // Phase transition haptic
        if let current = runner.currentPhaseID, current != lastPhaseID {
            lastPhaseID = current
            guard let kind = runner.phaseKind else { return }
            switch kind {
            case .work: playHapticSequence(.success, count: 3)
            case .rest: playHapticSequence(.directionDown, count: 3)
            case .warmup: playHapticSequence(.directionUp, count: 3)
            case .cooldown: playHapticSequence(.directionDown, count: 3)
            }
            audio.phaseTransition(soundsEnabled: soundsEnabled, isBoxing: isBoxing)
            decider.reset()
        }
    }

    func stop() {
        lastPhaseID = nil
        decider.reset()
        audio.stop()
    }

    private func playHapticSequence(_ type: WKHapticType, count: Int) {
        for index in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.14) { [device] in
                device.play(type)
            }
        }
    }
}
