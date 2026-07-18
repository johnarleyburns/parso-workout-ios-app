import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchIntervalView: View {
    let plan: IntervalPlan
    let kind: String
    let onDone: () -> Void

    @State private var runner: IntervalRunner
    @State private var haptics: WatchIntervalHaptics
    @State private var isShowingConfirmEnd = false
    @State private var showSummary = false

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(WatchWorkoutManager.self) private var watchManager

    init(plan: IntervalPlan, kind: String, onDone: @escaping () -> Void = {}) {
        self.plan = plan
        self.kind = kind
        self.onDone = onDone
        _runner = State(initialValue: IntervalRunner(plan: plan))
        _haptics = State(initialValue: WatchIntervalHaptics())
    }

    var body: some View {
        Group {
            if showSummary {
                summaryView
            } else {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    intervalContent(date: context.date)
                        .onChange(of: context.date) { _, d in advance(to: d) }
                }
                .alert("End Workout?", isPresented: $isShowingConfirmEnd) {
                    Button("End", role: .destructive) { endWorkout() }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .onAppear {
            watchManager.resetSavedSummary()
            watchManager.startWorkout(type: kind.lowercased(), cardioType: kind == "HIIT" ? .hiit : .boxing)
        }
        .onDisappear {
            if watchManager.isActive {
                watchManager.stopWorkout(save: false)
            }
            haptics.stop()
        }
    }

    // MARK: - Interval content

    private func intervalContent(date: Date) -> some View {
        ZStack {
            bgColor
                .ignoresSafeArea(.all)
                .animation(.easeInOut(duration: 0.3), value: runner.colorState)

            VStack(spacing: 2) {
                Spacer()

                Text(runner.phaseLabel.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(fgColor)

                Text(formatTime(runner.phaseRemaining))
                    .font(.system(size: 52, weight: .heavy, design: .monospaced))
                    .foregroundStyle(fgColor)
                    .accessibilityIdentifier("intervalCountdown")

                Text(roundLabel)
                    .font(.caption2)
                    .foregroundStyle(fgColor.opacity(0.8))

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

                Text("Total: \(formatTime(runner.overallRemaining))")
                    .font(.caption2)
                    .foregroundStyle(fgColor.opacity(0.5))
                    .padding(.top, 2)

                Spacer()

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

    // MARK: - Summary

    private var summaryView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            Text("Complete")
                .font(.headline)

            let sum = watchManager.savedSummary
            if let s = sum {
                summaryRow("Duration", formatTime(s.duration))
                if let avg = s.avgHR, let max = s.maxHR {
                    summaryRow("Avg / Max HR", "\(Int(avg)) / \(Int(max))")
                }
                summaryRow("Active kcal", "\(Int(s.activeKcal))")
            }

            Button("Save workout") {
                watchManager.stopWorkout(save: true)
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityLabel("Save workout")

            Button("Discard") {
                watchManager.stopWorkout(save: false)
                onDone()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Discard workout")
            Spacer()
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
    }

    // MARK: Color mapping

    private var bgColor: Color {
        switch runner.colorState {
        case .work: return .green
        case .warning: return .yellow
        case .imminent:
            if isLuminanceReduced {
                return .orange
            }
            return runner.phaseRemaining.truncatingRemainder(dividingBy: 0.4) < 0.2 ? .orange : .yellow
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

    private func advance(to date: Date) {
        runner.now = date
        guard !runner.isPaused, !runner.isComplete else { return }
        haptics.tick(runner: runner)
    }

    private func togglePause() {
        if runner.isPaused { runner.resume() } else { runner.pause() }
    }

    private func skipPhase() {
        runner.skipPhase()
        if runner.isComplete { transitionToSummary() }
    }

    private func addOneMinute() { runner.addTime(60) }

    private func endWorkout() {
        runner.end()
        transitionToSummary()
    }

    private func transitionToSummary() {
        let sum = watchManager.liveSummary()
        watchManager.savedSummary = WatchWorkoutManager.SavedWorkoutSummary(
            duration: sum.duration,
            avgHR: sum.avgHR,
            maxHR: sum.maxHR,
            activeKcal: sum.activeKcal,
            distanceMeters: sum.distanceMeters
        )
        showSummary = true
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
