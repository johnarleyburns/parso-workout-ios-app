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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(AppSettings.self) private var watchAppSettings

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
            watchManager.startHeartRatePolling()
        }
        .onDisappear {
            if scenePhase != .background, watchManager.isActive {
                watchManager.stopWorkout(save: false)
            }
            haptics.stop()
        }
    }

    // MARK: - Interval content

    private func intervalContent(date: Date) -> some View {
        GeometryReader { geo in
            let compact = geo.size.height < 190
            let timerSize = min(max(geo.size.height * 0.27, compact ? 38 : 42), 52)
            let controlSize: CGFloat = compact ? 34 : 38

            ZStack {
                bgColor
                    .ignoresSafeArea(.all)
                    .animation(.easeInOut(duration: 0.3), value: runner.colorState)

                VStack(spacing: compact ? 2 : 4) {
                    Text(runner.phaseLabel.uppercased())
                        .font(.caption2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(fgColor)

                    Text(formatTime(runner.phaseRemaining))
                        .font(.system(size: timerSize, weight: .heavy, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(fgColor)
                        .accessibilityIdentifier("intervalCountdown")

                    Text(roundLabel)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(fgColor.opacity(0.82))

                    metricStrip
                        .padding(.top, compact ? 0 : 1)

                    Spacer(minLength: compact ? 1 : 4)

                    controlsToolbar(controlSize: controlSize)
                        .frame(height: controlSize)
                }
                .padding(.horizontal, 8)
                .padding(.top, compact ? 2 : 5)
                .padding(.bottom, 5)
            }
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 7) {
            let bpmText = watchManager.currentBPM.map { "\(Int($0))" } ?? "--"
            Label(bpmText, systemImage: "heart.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.red.opacity(0.95))
                .accessibilityLabel(watchManager.currentBPM.map { "\(Int($0)) BPM" } ?? "Heart rate unavailable")
            Text("Tot \(formatTime(runner.overallRemaining))")
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(fgColor.opacity(0.62))
    }

    private func controlsToolbar(controlSize: CGFloat) -> some View {
        HStack(spacing: 7) {
            toolbarButton(accessibilityLabel: runner.isPaused ? "Resume" : "Pause", controlSize: controlSize) {
                togglePause()
            } label: {
                Image(systemName: runner.isPaused ? "play.fill" : "pause.fill")
            }

            toolbarButton(accessibilityLabel: "Skip phase", controlSize: controlSize) {
                skipPhase()
            } label: {
                Image(systemName: "forward.end.fill")
            }

            toolbarButton(accessibilityLabel: "Add one minute", controlSize: controlSize) {
                addOneMinute()
            } label: {
                Text("+1m")
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            toolbarButton(accessibilityLabel: "End workout", controlSize: controlSize, foreground: .red) {
                isShowingConfirmEnd = true
            } label: {
                Image(systemName: "stop.fill")
            }
        }
    }

    private func toolbarButton<LabelView: View>(accessibilityLabel: String,
                                                controlSize: CGFloat,
                                                foreground: Color? = nil,
                                                action: @escaping () -> Void,
                                                @ViewBuilder label: () -> LabelView) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: 17, weight: .bold))
                .frame(width: controlSize, height: controlSize)
                .foregroundStyle(foreground ?? fgColor)
                .background(.black.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
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
                if let avg = s.avgHR {
                    summaryRow("Avg HR", "\(Int(avg))")
                }
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
        guard !runner.isPaused else { return }
        haptics.tick(runner: runner, soundsEnabled: watchAppSettings.workoutSounds, isBoxing: isBoxingInterval)
        if runner.isComplete, !showSummary {
            transitionToSummary()
        }
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
            distanceMeters: sum.distanceMeters
        )
        showSummary = true
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var isBoxingInterval: Bool {
        kind.localizedCaseInsensitiveContains("boxing") || plan.name.localizedCaseInsensitiveContains("boxing")
    }
}
