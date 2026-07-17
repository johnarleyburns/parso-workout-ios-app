import SwiftUI
import CadenceCore
import CadenceFeatures

/// Full-screen color-coded HIIT / Boxing interval timer for watchOS.
///
/// Drives an `IntervalRunner` against a `TimelineView` so the timer stays
/// correct across backgrounding and Always-On (≤1 Hz update when wrist is down).
/// Whole-screen background colour = the interval signal, readable across the room.
///
/// Reuses pure engines from CadenceCore: `IntervalPlan` factories, `IntervalRunner`,
/// `IntervalSignal`, `FullScreenColorState`. Haptics via `WatchIntervalHaptics`.
struct WatchIntervalView: View {
    let plan: IntervalPlan
    let kind: String // "HIIT" or "Boxing" — drives haptic style

    @State private var runner: IntervalRunner
    @State private var haptics: WatchIntervalHaptics
    @State private var isShowingConfirmEnd = false
    @State private var isWaterLocked = false

    @Environment(\.dismiss) private var dismiss
    @Environment(WatchWorkoutManager.self) private var watchManager

    init(plan: IntervalPlan, kind: String) {
        self.plan = plan
        self.kind = kind
        _runner = State(initialValue: IntervalRunner(plan: plan))
        _haptics = State(initialValue: WatchIntervalHaptics())
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.5)) { timeline in
            ZStack {
                // Full-screen color background
                bgColor
                    .ignoresSafeArea(.all)
                    .animation(.easeInOut(duration: 0.3), value: runner.colorState)

                VStack(spacing: 2) {
                    Spacer()

                    // Phase label
                    Text(runner.phaseLabel.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(fgColor)

                    // Countdown
                    Text(formatTime(runner.phaseRemaining))
                        .font(.system(size: 52, weight: .heavy, design: .monospaced))
                        .foregroundStyle(fgColor)

                    // Round indicator
                    Text(roundLabel)
                        .font(.caption2)
                        .foregroundStyle(fgColor.opacity(0.8))

                    // Live BPM
                    if let bpm = watchManager.currentBPM {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                            Text("\(Int(bpm)) BPM")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(fgColor.opacity(0.6))
                        .padding(.top, 4)
                    }

                    // Total remaining
                    Text("Total: \(formatTime(runner.overallRemaining))")
                        .font(.caption2)
                        .foregroundStyle(fgColor.opacity(0.5))
                        .padding(.top, 2)

                    Spacer()

                    // Controls
                    HStack(spacing: 16) {
                        Button(action: togglePause) {
                            Image(systemName: runner.isPaused ? "play.fill" : "pause.fill")
                                .font(.title3)
                                .foregroundStyle(fgColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(runner.isPaused ? "Resume" : "Pause")

                        Button(action: skipPhase) {
                            Image(systemName: "forward.end.fill")
                                .font(.title3)
                                .foregroundStyle(fgColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Skip phase")

                        Button(action: addOneMinute) {
                            Text("+1m")
                                .font(.caption.bold())
                                .foregroundStyle(fgColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add one minute")

                        Button(role: .destructive, action: { isShowingConfirmEnd = true }) {
                            Image(systemName: "stop.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("End workout")
                    }
                    .padding(.bottom, 12)
                }
                .padding()
            }
        }
        .onChange(of: Date()) { _, newDate in
            runner.now = newDate
            guard !runner.isPaused, !runner.isComplete else { return }
            haptics.tick(runner: runner)
        }
        .onAppear {
            watchManager.startWorkout(type: kind.lowercased(), cardioType: kind == "HIIT" ? .hiit : .boxing)
        }
        .onDisappear {
            watchManager.stopWorkout()
            haptics.stop()
        }
        .alert("End Workout?", isPresented: $isShowingConfirmEnd) {
            Button("End", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Color mapping

    private var bgColor: Color {
        switch runner.colorState {
        case .work: return .green
        case .warning: return .yellow
        case .imminent: return runner.phaseRemaining.truncatingRemainder(dividingBy: 0.4) < 0.2 ? .orange : .yellow
        case .rest: return .red.opacity(0.85)
        case .neutral: return .blue
        }
    }

    private var fgColor: Color {
        switch runner.colorState {
        case .work, .warning, .imminent, .rest: return .white
        case .neutral: return .white
        }
    }

    // MARK: Round label

    private var roundLabel: String {
        guard let kind = runner.phaseKind else { return "Complete" }
        let workRounds = plan.workRounds
        let currentRound = plan.currentWorkRound(atElapsed: runner.elapsed)
        switch kind {
        case .work: return "Round \(currentRound)/\(workRounds)"
        case .rest: return "Rest (\(currentRound)/\(workRounds))"
        case .warmup: return "Warm-up"
        case .cooldown: return "Cool-down"
        }
    }

    // MARK: Actions

    private func togglePause() {
        if runner.isPaused { runner.resume() } else { runner.pause() }
    }

    private func skipPhase() {
        runner.skipPhase()
        if runner.isComplete { dismiss() }
    }

    private func addOneMinute() { runner.addTime(60) }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
