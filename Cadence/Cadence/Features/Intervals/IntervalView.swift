import SwiftUI
import CadenceCore
import CadenceFeatures

/// The flagship interval screen (field-testing §06): the WHOLE screen is the
/// signal — bright green during work, yellow in the last 30 s, flashing in the
/// last 3 s, red during rest — readable from across the room for low-vision use.
/// Meaning is always also carried by a large label + icon (never colour alone).
struct IntervalView: View {
    let plan: IntervalPlan
    let saveType: CardioType
    var captureHR = false
    /// Notifies the presenter (Home) the instant a workout is persisted, so its
    /// history-derived surfaces refresh without waiting for app re-entry.
    var onSaved: (CardioWorkout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var runner: IntervalRunner
    @State private var cues = IntervalCues()
    @State private var cueScheduler: IntervalCueScheduler?
    @State private var flashOn = false
    @State private var finished = false
    @State private var finishedSummary: WorkoutSummaryData?
    @State private var hrSamples: [HRSamplePoint] = []
    @State private var lastHRSecond = -1
    @State private var showSkipConfirmation = false
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(plan: IntervalPlan, saveType: CardioType, captureHR: Bool = false,
         onSaved: @escaping (CardioWorkout) -> Void = { _ in }) {
        self.plan = plan
        self.saveType = saveType
        self.captureHR = captureHR
        self.onSaved = onSaved
        _runner = State(initialValue: IntervalRunner(plan: plan))
    }

    private var state: FullScreenColorState { runner.colorState }
    private var isImminent: Bool { state == .imminent }

    var body: some View {
        if let finishedSummary {
            WorkoutSummaryView(data: finishedSummary, onDone: { dismiss() })
        } else {
            runnerView
                .keepAwake()
                .onAppear {
                    runner.restart()
                    let scheduler = IntervalCueScheduler(runner: runner, cues: cues)
                    cueScheduler = scheduler
                    scheduler.start()
                }
        }
    }

    private var runnerView: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 16) {
                // The chosen protocol's name stays visible the whole workout.
                HStack {
                    WallClockLabel()
                    Spacer()
                }
                .padding(.horizontal)
                planNamePill
                    .padding(.top, 8)
                    .accessibilityIdentifier("interval.planName")
                Spacer()
                Image(systemName: icon).scaledSystemFont(64, relativeTo: .largeTitle, weight: .bold)
                Text(label.uppercased())
                    .scaledSystemFont(40, relativeTo: .largeTitle, weight: .heavy, design: .rounded)
                    .minimumScaleFactor(0.5).lineLimit(2).multilineTextAlignment(.center)
                    .accessibilityIdentifier("interval.phaseLabel")
                Text(Format.duration(runner.phaseRemaining))
                    .scaledSystemFont(120, relativeTo: .largeTitle, weight: .black, design: .rounded)
                    .monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
                    .accessibilityIdentifier("interval.countdown")
                Text("Total left \(Format.duration(runner.overallRemaining))")
                    .font(.headline).opacity(0.85)
                if let bpm = model.hrm.currentBPM, bpm > 0 {
                    Label("\(Int(bpm)) bpm", systemImage: "heart.fill")
                        .font(.headline).opacity(0.9)
                        .accessibilityIdentifier("interval.bpm")
                }
                Spacer()

                // Skip the current phase (warm-up/work/rest/cool-down) — feedback
                // batch 5. Big hit target above the Pause/End pair.
                HStack(spacing: 16) {
                    Button(action: { showSkipConfirmation = true }) {
                        Label("Skip", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .cadenceGlassButton(tint: .black.opacity(0.4))
                    .accessibilityIdentifier("interval.skip")
                    .accessibilityLabel("Skip phase")

                    if runner.phaseKind == .warmup || runner.phaseKind == .cooldown {
                        Button {
                            runner.addTime(60)
                        } label: {
                            Label("+1 min", systemImage: "plus")
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .cadenceGlassButton(tint: .black.opacity(0.4))
                        .accessibilityIdentifier("interval.addMinute")
                        .accessibilityLabel("Add one minute")
                    }
                }

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
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(runner.phaseRemaining)) seconds left")
        .statusBarHidden()
        .confirmationDialog("Skip this phase?", isPresented: $showSkipConfirmation, titleVisibility: .visible) {
            Button("Skip", role: .destructive, action: skipPhase)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will advance to the next phase.")
        }
        .onAppear { cues.spokenEnabled = settings.spokenCues; cues.isBoxing = saveType == .boxing }
        .onReceive(tick) { _ in advance() }
        .onChange(of: runner.currentPhaseID) { _, _ in
            if let kind = runner.phaseKind { cues.phaseChanged(to: kind, label: runner.phaseLabel) }
            cueScheduler?.resetForNewPhase()
        }
        .onDisappear {
            cueScheduler?.stop()
            cues.deactivate()
        }
    }

    // MARK: Colour palette (label + icon also convey meaning, NFR-2)

    @ViewBuilder
    private var planNamePill: some View {
        let pill = Text(plan.name.uppercased())
            .font(.title3.weight(.heavy))
            .padding(.horizontal, 14).padding(.vertical, 6)
        if GlassFeature.isEnabled, #available(iOS 26.0, *) {
            pill.glassEffect(.regular, in: Capsule())
        } else {
            pill.background(.black.opacity(0.25), in: Capsule())
        }
    }

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
        if !runner.isPaused {
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
        // Cue scheduling (30 s warning, countdown ticks) is handled by
        // IntervalCueScheduler so it fires reliably in the background.

        if runner.isComplete && !finished { Task { await finish() } }
    }

    private func togglePause() {
        runner.isPaused ? runner.resume() : runner.pause()
    }

    /// Skips the active phase and re-arms the cue trackers for the new phase. When
    /// the skip ends the workout (skipping the final phase), finish with the
    /// *pre-skip* elapsed so the cut-short phase records its actual time, not the
    /// skipped-to-end length (feedback batch 6).
    private func skipPhase() {
        let preSkipElapsed = runner.elapsed
        runner.skipPhase()
        cueScheduler?.resetForNewPhase()
        if runner.isComplete && !finished { Task { await finish(elapsedOverride: preSkipElapsed) } }
    }

    private func finish(elapsedOverride: TimeInterval? = nil) async {
        guard !finished else { return }
        finished = true
        runner.end()
        cues.completed()
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        model.stopWatchWorkout()
        let start = runner.clock.startedAt
        let end = Date()
        // Capture the protocol structure (rounds, work/rest, warm-up/cool-down, and
        // how many work rounds were actually finished) so history shows the detail
        // (feedback batch 4 / roadmap P5). Warm-up/cool-down reflect *actual* time
        // consumed (feedback batch 6).
        let interval = IntervalSummary.from(plan: plan, elapsed: elapsedOverride ?? runner.elapsed)
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
            onSaved(saved)
            finishedSummary = WorkoutSummaryData.from(cardio: saved)
        } else {
            dismiss()
        }
    }
}
