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
    @State private var page: Page = .main

    enum Page: Hashable { case controls, main, heart }

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    pager
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
            watchManager.beginCardioWorkout(type: kind.lowercased(),
                                            cardioType: kind == "HIIT" ? .hiit : .boxing)
            watchManager.startHeartRatePolling()
            WatchWorkoutVoiceCoach.shared.speak(
                .workoutStarted(title: kind), enabled: watchAppSettings.spokenCues)
        }
        .onDisappear {
            if scenePhase != .background {
                watchManager.finishCardioSession(save: false)
            }
            haptics.stop()
        }
        .ownsWatchWorkoutSession()
    }

    // MARK: - Pager (I1: Controls ◂ Interval ▸ Heart, like strength and steady cardio)

    private var pager: some View {
        TabView(selection: $page) {
            controlsPage.tag(Page.controls)
            intervalPage.tag(Page.main)
            WatchHeartPage().tag(Page.heart)
        }
        .tabViewStyle(.page)
    }

    /// Watch redesign §5 I1 — phase is colour **and** word (red Work, green Rest, amber when work is
    /// ending, blue for warm-up/cool-down), the countdown huge, the round in the title, heart rate
    /// and zone underneath. Always On drops the gradient and keeps the numbers.
    private var intervalPage: some View {
        let tone = WatchIntervalPhaseTone.tone(for: runner.colorState)
        return ZStack {
            if !isLuminanceReduced {
                RadialGradient(colors: [toneColor(tone).opacity(0.75), .black], center: .top,
                               startRadius: 0, endRadius: 190)
                    .ignoresSafeArea()
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: tone)
            }
            VStack(spacing: 2) {
                Text(titleLine)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 2)
                Text(runner.phaseLabel)
                    .font(.headline)
                    .foregroundStyle(toneInk(tone))
                Text(formatTime(runner.phaseRemaining))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("intervalCountdown")
                heartLine
                if !isLuminanceReduced { zoneBar.padding(.horizontal, 14).padding(.top, 6) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(runner.phaseLabel), \(formatTime(runner.phaseRemaining)) left, \(titleLine)"))
    }

    private var titleLine: String {
        "\(kind) · \(roundLabel)"
    }

    private var heartLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill").foregroundStyle(WatchTone.heart)
            Text(watchManager.currentBPM.map { "\(Int($0))" } ?? "--").monospacedDigit()
            if let zone = heartZone { Text(verbatim: "· Z\(zone)") }
        }
        .font(.footnote.weight(.semibold))
        .accessibilityElement(children: .combine)
    }

    private var heartZone: Int? {
        guard let bpm = watchManager.currentBPM, bpm > 0 else { return nil }
        return CardioMath.hrZone(bpm: bpm, maxHR: CardioMath.defaultMaxHR(age: watchAppSettings.userAge))
    }

    private var zoneBar: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { zone in
                Capsule()
                    .fill(zone <= (heartZone ?? 0) ? WatchTone.heart : Color.white.opacity(0.18))
                    .frame(height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    private var controlsPage: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(formatTime(runner.overallRemaining))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(WatchTone.accent)
                    .accessibilityLabel(Text("\(formatTime(runner.overallRemaining)) left in the workout"))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    controlTile(runner.isPaused ? "Resume" : "Pause",
                                systemImage: runner.isPaused ? "play.fill" : "pause.fill",
                                identifier: "watchInterval.pause") { togglePause() }
                    controlTile("End", systemImage: "xmark", destructive: true,
                                identifier: "watchInterval.end") { isShowingConfirmEnd = true }
                    controlTile("Skip phase", systemImage: "forward.end.fill",
                                identifier: "watchInterval.skip") { skipPhase(); page = .main }
                    controlTile("+1 min", systemImage: "plus",
                                identifier: "watchInterval.addMinute") { addOneMinute(); page = .main }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func controlTile(_ title: LocalizedStringKey, systemImage: String, destructive: Bool = false,
                             identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            WatchHaptics.tap()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title3)
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(RoundedRectangle(cornerRadius: 14).fill(destructive ? Color.red.opacity(0.18) : WatchTone.surface))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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
                summaryRow(String(localized: "Duration"), formatTime(s.duration))
                if let avg = s.avgHR {
                    summaryRow(String(localized: "Avg HR"), "\(Int(avg))")
                }
            }

            Button("Save workout") {
                if let s = watchManager.savedSummary {
                    watchManager.enqueueCardioCompletion(type: intervalCardioType, summary: s)
                }
                watchManager.finishCardioSession(save: true)
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityLabel("Save workout")

            Button("Discard") {
                watchManager.finishCardioSession(save: false)
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

    private func toneColor(_ tone: WatchIntervalPhaseTone) -> Color {
        switch tone {
        case .work: Color(red: 0.75, green: 0.16, blue: 0.11)
        case .ending: Color(red: 0.85, green: 0.55, blue: 0.08)
        case .rest: Color(red: 0.11, green: 0.6, blue: 0.3)
        case .easy: Color(red: 0.12, green: 0.35, blue: 0.75)
        }
    }

    private func toneInk(_ tone: WatchIntervalPhaseTone) -> Color {
        switch tone {
        case .work: Color(red: 1, green: 0.7, blue: 0.66)
        case .ending: Color(red: 1, green: 0.85, blue: 0.5)
        case .rest: Color(red: 0.62, green: 0.95, blue: 0.77)
        case .easy: Color(red: 0.7, green: 0.82, blue: 1)
        }
    }

    private var roundLabel: String {
        guard let kind = runner.phaseKind else { return String(localized: "Complete") }
        let workRounds = plan.workRounds
        let currentRound = plan.currentWorkRound(atElapsed: runner.elapsed)
        switch kind {
        case .work: return String(localized: "Round \(currentRound)/\(workRounds)")
        case .rest: return String(localized: "Rest (\(currentRound)/\(workRounds))")
        case .warmup: return String(localized: "Warm-up")
        case .cooldown: return String(localized: "Cool-down")
        }
    }

    // MARK: Actions

    private func advance(to date: Date) {
        runner.now = date
        guard !runner.isPaused else { return }
        haptics.tick(runner: runner,
                     soundsEnabled: watchAppSettings.workoutSounds,
                     spokenEnabled: watchAppSettings.spokenCues,
                     isBoxing: isBoxingInterval,
                     currentRound: plan.currentWorkRound(atElapsed: runner.elapsed))
        if runner.isComplete, !showSummary {
            transitionToSummary()
        }
    }

    private func togglePause() {
        if runner.isPaused {
            runner.resume()
            WatchWorkoutVoiceCoach.shared.speak(.resumed, enabled: watchAppSettings.spokenCues)
        } else {
            runner.pause()
            WatchWorkoutVoiceCoach.shared.speak(.paused, enabled: watchAppSettings.spokenCues)
        }
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
        WatchWorkoutVoiceCoach.shared.speak(.workoutComplete,
                                            enabled: watchAppSettings.spokenCues)
        let sum = watchManager.liveSummary()
        watchManager.savedSummary = WatchWorkoutManager.SavedWorkoutSummary(
            duration: sum.duration,
            avgHR: sum.avgHR,
            maxHR: sum.maxHR,
            distanceMeters: sum.distanceMeters,
            hrSamples: watchManager.currentHRSamplesForSummary
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

    private var intervalCardioType: CardioType {
        kind.localizedCaseInsensitiveContains("boxing") ? .boxing : .hiit
    }
}
