import Foundation
import CadenceCore

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
    private var lastWarnedPhase: Int?
    private var lastTickSecond = -1

    init(runner: IntervalRunner, cues: IntervalCues) {
        self.runner = runner
        self.cues = cues
    }

    func start() {
        stop()
        // Fire every 0.5 s to catch 30 s warning and 3 s countdown boundaries
        // accurately. The runner's wall-clock phase boundaries drive precision.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Ensure the Timer fires even during scrolling / background run loops.
        if let t = timer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastWarnedPhase = nil
        lastTickSecond = -1
    }

    /// Re-arm trackers (called after a phase skip so warnings/ticks fire for the
    /// new phase).
    func resetForNewPhase() {
        lastWarnedPhase = nil
        lastTickSecond = -1
    }

    // MARK: - Internal tick

    private func tick() {
        guard !runner.isPaused, !runner.isComplete else { return }

        let secs = Int(runner.phaseRemaining.rounded(.up))

        // 30-second warning (once per work phase)
        if runner.phaseKind == .work, secs == 30, runner.currentPhaseID != lastWarnedPhase {
            cues.warning()
            lastWarnedPhase = runner.currentPhaseID
        }

        // Countdown ticks on the final 3 whole seconds of a work phase
        if runner.phaseKind == .work, (1...3).contains(secs), secs != lastTickSecond {
            cues.countdownTick()
            lastTickSecond = secs
        } else if secs > 3 {
            lastTickSecond = -1
        }
    }
}
