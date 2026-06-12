import SwiftUI
import CadenceCore

/// The flagship interval screen (field-testing §06): the WHOLE screen is the
/// signal — bright green during work, yellow in the last 30 s, flashing in the
/// last 3 s, red during rest — readable from across the room for low-vision use.
/// Meaning is always also carried by a large label + icon (never colour alone).
struct IntervalView: View {
    let plan: IntervalPlan
    /// `.hiit` or `.boxing` — for the saved HealthKit summary.
    let saveType: CardioType

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var runner: IntervalRunner
    @State private var cues = IntervalCues()
    @State private var flashOn = false
    @State private var lastTickSecond = -1
    @State private var lastWarnedPhase: Int?
    @State private var finished = false
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(plan: IntervalPlan, saveType: CardioType) {
        self.plan = plan
        self.saveType = saveType
        _runner = State(initialValue: IntervalRunner(plan: plan))
    }

    private var state: FullScreenColorState { runner.colorState }
    private var isImminent: Bool { state == .imminent }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 16) {
                // The chosen protocol's name stays visible the whole workout.
                Text(plan.name.uppercased())
                    .font(.title3.weight(.heavy))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(.black.opacity(0.25), in: Capsule())
                    .padding(.top, 8)
                    .accessibilityIdentifier("interval.planName")
                Spacer()
                Image(systemName: icon).font(.system(size: 64, weight: .bold))
                Text(label.uppercased())
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5).lineLimit(2).multilineTextAlignment(.center)
                Text(Format.duration(runner.phaseRemaining))
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
                    .accessibilityIdentifier("interval.countdown")
                Text("Total left \(Format.duration(runner.overallRemaining))")
                    .font(.headline).opacity(0.85)
                Spacer()

                WorkoutControlBar(
                    isPaused: runner.isPaused,
                    onPauseToggle: togglePause,
                    onEnd: { Task { await finish() } },
                    idPrefix: "interval",
                    endTint: .black.opacity(0.4),
                    pauseTint: .black.opacity(0.4)
                )
                .padding(.bottom)
            }
            .foregroundStyle(.white)
            .padding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label), \(Int(runner.phaseRemaining)) seconds left")
        .statusBarHidden()
        .onAppear { cues.spokenEnabled = settings.spokenCues }
        .onReceive(tick) { _ in advance() }
        .onChange(of: runner.currentPhaseID) { _, _ in
            if let kind = runner.phaseKind { cues.phaseChanged(to: kind, label: runner.phaseLabel) }
        }
        .onDisappear { cues.deactivate() }
    }

    // MARK: Colour palette (label + icon also convey meaning, NFR-2)

    private var background: Color {
        // Color-blind-safe palette swaps green/red for blue/purple (decision #20);
        // meaning is also carried by the label + icon, never colour alone.
        let cb = settings.intervalColorBlind
        switch state {
        case .work: return cb ? .blue : .green
        case .warning: return .yellow
        case .imminent: return (reduceMotion ? .yellow : (flashOn ? .yellow : .orange))
        case .rest: return cb ? .purple : .red
        case .neutral: return cb ? .gray : .blue
        }
    }
    private var icon: String {
        switch state {
        case .work, .warning, .imminent: return "bolt.fill"
        case .rest: return "pause.circle.fill"
        case .neutral: return "figure.cooldown"
        }
    }
    private var label: String { runner.phaseLabel.isEmpty ? "Get Ready" : runner.phaseLabel }

    // MARK: Loop

    private func advance() {
        runner.now = Date()
        // Flash toggle for the last-3s imminent state (honours Reduce Motion).
        if isImminent && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) { flashOn.toggle() }
        } else { flashOn = false }
        // 30-second warning bell (once) during a work phase.
        let secs = Int(runner.phaseRemaining.rounded(.up))
        if runner.phaseKind == .work, secs == 30, runner.currentPhaseID != lastWarnedPhase {
            cues.warning(); lastWarnedPhase = runner.currentPhaseID
        }
        // Countdown ticks on the final 3 whole seconds of a work phase.
        if runner.phaseKind == .work, (1...3).contains(secs), secs != lastTickSecond {
            cues.countdownTick(); lastTickSecond = secs
        } else if secs > 3 { lastTickSecond = -1 }

        if runner.isComplete && !finished { Task { await finish() } }
    }

    private func togglePause() {
        runner.isPaused ? runner.resume() : runner.pause()
    }

    private func finish() async {
        guard !finished else { return }
        finished = true
        runner.end()
        cues.completed()
        let start = runner.clock.startedAt
        let end = Date()
        let summary = CardioWorkoutSummary(id: UUID(), type: saveType, start: start, end: end,
                                           distanceMeters: nil,
                                           activeEnergyKcal: CardioMath.estimateCalories(
                                               type: saveType, seconds: end.timeIntervalSince(start), avgHR: nil),
                                           hrSamples: [], route: [])
        let hkID = await model.health.saveCardioWorkout(summary)
        try? WorkoutRepository.saveRecordedCardio(summary, source: .iphone,
                                                  healthKitWorkoutUUID: hkID, in: context)
        dismiss()
    }
}
