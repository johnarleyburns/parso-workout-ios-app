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
    @State private var finishedSummary: WorkoutSummaryData?
    // HR (feedback batch 5): the pre-workout gate decides whether we capture HR; if
    // so we sample the strap's BPM once per whole second into `hrSamples`.
    @State private var showingHRGate = true
    @State private var captureHR = false
    @State private var hrSamples: [HRSamplePoint] = []
    @State private var lastHRSecond = -1
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(plan: IntervalPlan, saveType: CardioType) {
        self.plan = plan
        self.saveType = saveType
        _runner = State(initialValue: IntervalRunner(plan: plan))
    }

    private var state: FullScreenColorState { runner.colorState }
    private var isImminent: Bool { state == .imminent }

    var body: some View {
        if let finishedSummary {
            // A3 — the interval session is saved; show its summary.
            WorkoutSummaryView(data: finishedSummary, onDone: { dismiss() })
        } else if showingHRGate {
            // Pre-workout HR connect screen (feedback batch 5). The runner's clock
            // only starts once the gate is passed, so setup time isn't counted.
            PreWorkoutHRView { useHR in
                captureHR = useHR
                runner.restart()
                showingHRGate = false
            }
        } else {
            runnerView
        }
    }

    private var runnerView: some View {
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
                    .accessibilityIdentifier("interval.phaseLabel")
                Text(Format.duration(runner.phaseRemaining))
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
                    .accessibilityIdentifier("interval.countdown")
                Text("Total left \(Format.duration(runner.overallRemaining))")
                    .font(.headline).opacity(0.85)
                if captureHR, let bpm = model.hrm.currentBPM, bpm > 0 {
                    Label("\(Int(bpm)) bpm", systemImage: "heart.fill")
                        .font(.headline).opacity(0.9)
                        .accessibilityIdentifier("interval.bpm")
                }
                Spacer()

                // Skip the current phase (warm-up/work/rest/cool-down) — feedback
                // batch 5. Big hit target above the Pause/End pair.
                Button(action: skipPhase) {
                    Label("Skip", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered).controlSize(.large)
                .tint(.black.opacity(0.4))
                .accessibilityIdentifier("interval.skip")
                .accessibilityLabel("Skip phase")

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
        // Sample the strap's HR once per whole elapsed second (feedback batch 5).
        if captureHR, !runner.isPaused {
            let whole = Int(runner.elapsed)
            if whole != lastHRSecond, let bpm = model.hrm.currentBPM, bpm > 0 {
                hrSamples.append(HRSamplePoint(t: TimeInterval(whole), bpm: bpm))
                lastHRSecond = whole
            }
        }
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

    /// Skips the active phase and re-arms the cue trackers for the new phase.
    private func skipPhase() {
        runner.skipPhase()
        lastWarnedPhase = nil
        lastTickSecond = -1
        if runner.isComplete && !finished { Task { await finish() } }
    }

    private func finish() async {
        guard !finished else { return }
        finished = true
        runner.end()
        cues.completed()
        let start = runner.clock.startedAt
        let end = Date()
        // Capture the protocol structure (rounds, work/rest, warm-up/cool-down, and
        // how many work rounds were actually finished) so history shows the detail
        // (feedback batch 4 / roadmap P5).
        let interval = IntervalSummary.from(plan: plan, elapsed: runner.elapsed)
        // Real HR captured from the strap during the workout (feedback batch 5).
        let hr = HRSampling.downsample(hrSamples)
        let bpms = hr.map(\.bpm).filter { $0 > 0 }
        let avgHR = bpms.isEmpty ? nil : bpms.reduce(0, +) / Double(bpms.count)
        let summary = CardioWorkoutSummary(id: UUID(), type: saveType, start: start, end: end,
                                           distanceMeters: nil,
                                           activeEnergyKcal: CardioMath.estimateCalories(
                                               type: saveType, seconds: end.timeIntervalSince(start), avgHR: avgHR),
                                           hrSamples: hr, route: [],
                                           intervalSummary: interval)
        let hkID = await model.health.saveCardioWorkout(summary)
        let saved = try? WorkoutRepository.saveRecordedCardio(summary, source: .iphone,
                                                              healthKitWorkoutUUID: hkID, in: context)
        if let saved {
            finishedSummary = WorkoutSummaryData.from(cardio: saved)
        } else {
            dismiss()
        }
    }
}
