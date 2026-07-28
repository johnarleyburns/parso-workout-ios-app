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
    private var didPlayCompletion = false

    func tick(runner: IntervalRunner, soundsEnabled: Bool, isBoxing: Bool) {
        guard !runner.isComplete else {
            if !didPlayCompletion {
                playHapticSequence(.success, count: 3)
                audio.phaseTransition(soundsEnabled: soundsEnabled, isBoxing: isBoxing)
                didPlayCompletion = true
                decider = IntervalCueDecider()
            }
            return
        }
        didPlayCompletion = false

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
            case .phaseTransition(let kind):
                switch kind {
                case .work:
                    device.play(.notification)
                    playHapticSequence(.success, count: 2)
                case .rest:
                    device.play(.notification)
                    playHapticSequence(.directionDown, count: 2)
                case .warmup:
                    playHapticSequence(.directionUp, count: 2)
                case .cooldown:
                    playHapticSequence(.directionDown, count: 2)
                }
                audio.phaseTransition(soundsEnabled: soundsEnabled, isBoxing: isBoxing)
                decider.reset()
            }
        }
    }

    func stop() {
        decider = IntervalCueDecider()
        didPlayCompletion = false
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
