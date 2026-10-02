import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchCardioSessionView: View {
    let kind: WorkoutConfigurationSpec.CardioKind
    let spec: WorkoutConfigurationSpec
    let onDone: () -> Void

    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(AppSettings.self) private var watchSettings

    @State private var metrics: CardioMetricsModel?
    @State private var pendingSummary: WatchWorkoutManager.SavedWorkoutSummary?
    @State private var isShowingConfirmEnd = false
    @State private var page: Page = .metrics

    enum Page: Hashable { case controls, metrics, heart }

    var body: some View {
        Group {
            if let summary = pendingSummary, let metrics {
                WatchCardioSummaryView(
                    summary: summary,
                    metrics: metrics,
                    lapText: lapSummaryText,
                    onSave: save,
                    onDiscard: discard
                )
            } else if let metrics {
                activePages(metrics)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if metrics == nil {
                metrics = CardioMetricsModel(kind: kind, unit: watchSettings.unit, distanceUnit: watchSettings.distanceUnit,
                                             heartRateEnabled: spec.heartRateEnabled, gpsEnabled: spec.usesGPS)
                WatchWorkoutVoiceCoach.shared.speak(
                    .workoutStarted(title: String(describing: kind)), enabled: watchSettings.spokenCues)
            }
        }
        .onDisappear {
            WatchWorkoutVoiceCoach.shared.stop()
            if case nil = pendingSummary {
                watchManager.finishCardioSession(save: false)
            }
        }
        .alert("End Workout?", isPresented: $isShowingConfirmEnd) {
            Button("End", role: .destructive) { prepareSummary() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func activePages(_ metrics: CardioMetricsModel) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            // I2 — the same pager as strength and intervals: Controls ◂ Metrics ▸ Heart.
            TabView(selection: $page) {
                WatchCardioControlsView(
                    isSwim: kind == .swim,
                    isPaused: watchManager.isPaused,
                    onEnd: { isShowingConfirmEnd = true },
                    onPause: {
                        watchManager.togglePause()
                        WatchWorkoutVoiceCoach.shared.speak(
                            watchManager.isPaused ? .paused : .resumed,
                            enabled: watchSettings.spokenCues)
                        update(metrics)
                    },
                    onLock: { watchManager.enableWaterLock() },
                    onLap: { watchManager.incrementManualLap(); update(metrics) }
                )
                .tag(Page.controls)
                WatchCardioView(metrics: metrics, kind: kind, spec: spec)
                    .navigationTitle(Text(kindTitle))
                    .tag(Page.metrics)
                WatchHeartPage()
                    .tag(Page.heart)
            }
            .tabViewStyle(.page)
            .onAppear { update(metrics) }
            .onChange(of: context.date) { _, _ in update(metrics) }
        }
    }

    private func update(_ metrics: CardioMetricsModel) {
        let live = watchManager.liveSummary()
        metrics.updateElapsed(live.duration)
        metrics.updateHR(watchManager.currentBPM)
        metrics.updateDistance(watchManager.distanceMeters)
        metrics.lapCount = watchManager.autoLapCount
        metrics.manualLapCount = watchManager.manualLapCount
        metrics.setAutoPaused(watchManager.isPaused)
    }

    private func prepareSummary() {
        WatchWorkoutVoiceCoach.shared.speak(
            .workoutComplete, enabled: watchSettings.spokenCues)
        if let metrics { update(metrics) }
        let live = watchManager.liveSummary()
        pendingSummary = WatchWorkoutManager.SavedWorkoutSummary(
            duration: live.duration,
            avgHR: live.avgHR,
            maxHR: live.maxHR,
            distanceMeters: live.distanceMeters,
            hrSamples: watchManager.currentHRSamplesForSummary
        )
    }

    private func save() {
        if let summary = pendingSummary {
            watchManager.enqueueCardioCompletion(type: cardioType, summary: summary)
        }
        watchManager.finishCardioSession(save: true)
        onDone()
    }

    private var cardioType: CardioType {
        switch kind {
        case .run: return .run
        case .walk: return .walk
        case .cycle: return .cycle
        case .swim: return .swim
        case .hiit: return .hiit
        case .boxing: return .boxing
        case .rowing: return .rowing
        case .other: return .other
        case .strength: return .other
        }
    }

    private func discard() {
        WatchWorkoutVoiceCoach.shared.stop()
        watchManager.finishCardioSession(save: false)
        onDone()
    }

    private var kindTitle: String {
        let type = cardioType
        guard spec.usesGPS else { return type.displayName }
        return spec.location == .outdoor ? String(localized: "Outdoor \(type.displayName)")
                                         : type.displayName
    }

    private var lapSummaryText: String? {
        guard kind == .swim else { return nil }
        let total = watchManager.autoLapCount + watchManager.manualLapCount
        return "\(total)"
    }
}
