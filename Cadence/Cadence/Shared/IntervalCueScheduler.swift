import Foundation
import CadenceCore
import CadenceFeatures

/// Drives interval audio/haptic cues from wall-clock phase boundaries instead of
/// SwiftUI view ticks, so cues fire reliably in the background when `audio`
/// background mode + `.playback` category are active.
///
/// The runner is the source of truth for elapsed/phase state; the scheduler only
/// fires time-based events it hasn't yet fired for the current phase.
@MainActor
final class IntervalCueScheduler {
    private let runner: IntervalRunner
    private let cues: IntervalCues

    private var timer: Timer?
    private var decider = IntervalCueDecider()

    init(runner: IntervalRunner, cues: IntervalCues) {
        self.runner = runner
        self.cues = cues
    }

    func start() {
        stop()
        // Fire every 0.5 s to catch 30 s warning and 3 s countdown boundaries
        // accurately. The runner's wall-clock phase boundaries drive precision.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Ensure the Timer fires even during scrolling / background run loops.
        if let t = timer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        decider.reset()
    }

    /// Re-arm trackers (called after a phase skip so warnings/ticks fire for the
    /// new phase).
    func resetForNewPhase() {
        decider.reset()
    }

    // MARK: - Internal tick

    private func tick() {
        let cuesToFire = decider.cues(
            phaseKind: runner.phaseKind,
            currentPhaseID: runner.currentPhaseID,
            phaseRemaining: runner.phaseRemaining,
            isPaused: runner.isPaused,
            isComplete: runner.isComplete)
        for cue in cuesToFire {
            switch cue {
            case .warning: cues.warning()
            case .countdownTick: cues.countdownTick()
            }
        }
    }
}
