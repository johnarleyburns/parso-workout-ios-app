import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

extension HomeView {
    @ViewBuilder
    var dashboardTransientOverlays: some View {
        // HR gate — appears before the get-ready countdown so the user can
        // connect HR, see live data, then press Start Workout.
        if let kind = hrGateKind {
            PreWorkoutHRView(
                workoutType: kind.cardioType,
                onContinue: { source in
                    hrGateKind = nil
                    captureHR = source != .none
                    proceedFromHRGate(kind, useHR: source != .none)
                },
                onCancel: { hrGateKind = nil })
                .transition(.identity)
                .zIndex(2)
        }
        if let p = pending {
            PreWorkoutCountdownView(
                seconds: settings.preWorkoutCountdown,
                onStart: {
                    let k = p.kind
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { launch(k); pending = nil }
                },
                onCancel: { pending = nil })
                .transition(.identity)
                .zIndex(1)
        }
    }

    /// Immersive warm-up cover. It is intentionally not an overlay: workout
    /// phases must hide the app tab bar and cannot be swiped away.
    var warmupPhaseOverlay: some View {
        GuidedPhaseOverlay(
            title: String(localized: "Warm Up"),
            minutes: pendingPlan?.warmupMinutes ?? settings.warmupMinutes,
            tint: .orange,
            idPrefix: "warmup",
            soundsEnabled: settings.workoutSounds,
            finishSystemImage: "chevron.forward.2",
            onFinish: { secs in finishWarmup(elapsedSeconds: secs, startCue: .countdown) },
            onSkip: { secs in
                WorkoutCues.cancelPendingSounds()
                finishWarmup(elapsedSeconds: secs, startCue: .single)
            },
            liveMetric: AnyView(SessionLiveHRBand(showsEmptyState: true)))
    }
}
