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

}
