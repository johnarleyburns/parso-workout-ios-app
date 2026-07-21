import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchCardioSessionView: View {
    let kind: WorkoutConfigurationSpec.CardioKind
    let onDone: () -> Void

    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(AppSettings.self) private var watchSettings

    @State private var metrics: CardioMetricsModel?
    @State private var pendingSummary: WatchWorkoutManager.SavedWorkoutSummary?
    @State private var isShowingConfirmEnd = false

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
                metrics = CardioMetricsModel(kind: kind, unit: watchSettings.unit, distanceUnit: watchSettings.distanceUnit)
            }
        }
        .onDisappear {
            if case nil = pendingSummary, watchManager.isActive {
                watchManager.stopWorkout(save: false)
            }
        }
        .alert("End Workout?", isPresented: $isShowingConfirmEnd) {
            Button("End", role: .destructive) { prepareSummary() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func activePages(_ metrics: CardioMetricsModel) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            TabView {
                WatchCardioView(metrics: metrics, kind: kind)
                WatchCardioControlsView(
                    isSwim: kind == .swim,
                    isPaused: watchManager.isPaused,
                    onEnd: { isShowingConfirmEnd = true },
                    onPause: { watchManager.togglePause(); update(metrics) },
                    onLock: { watchManager.enableWaterLock() },
                    onLap: { watchManager.incrementManualLap(); update(metrics) }
                )
            }
            .onAppear { update(metrics) }
            .onChange(of: context.date) { _, _ in update(metrics) }
        }
    }

    private func update(_ metrics: CardioMetricsModel) {
        let live = watchManager.liveSummary()
        metrics.updateElapsed(live.duration)
        metrics.updateHR(watchManager.currentBPM)
        metrics.updateKcal(watchManager.activeEnergyKcal)
        metrics.updateDistance(watchManager.distanceMeters)
        metrics.lapCount = watchManager.autoLapCount
        metrics.manualLapCount = watchManager.manualLapCount
        metrics.setAutoPaused(watchManager.isPaused)
    }

    private func prepareSummary() {
        if let metrics { update(metrics) }
        let live = watchManager.liveSummary()
        pendingSummary = WatchWorkoutManager.SavedWorkoutSummary(
            duration: live.duration,
            avgHR: live.avgHR,
            maxHR: live.maxHR,
            activeKcal: live.activeKcal,
            distanceMeters: live.distanceMeters
        )
    }

    private func save() {
        watchManager.stopWorkout(save: true)
        onDone()
    }

    private func discard() {
        watchManager.stopWorkout(save: false)
        onDone()
    }

    private var lapSummaryText: String? {
        guard kind == .swim else { return nil }
        let total = watchManager.autoLapCount + watchManager.manualLapCount
        return "\(total)"
    }
}
