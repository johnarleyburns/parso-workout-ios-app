import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

extension HomeView {
    func presentWarmup() {
        let minutes = pendingPlan?.warmupMinutes ?? settings.warmupMinutes
        warmupCover.present(minutes: minutes,
                            soundsEnabled: settings.workoutSounds,
                            onFinish: { secs in
                                finishWarmup(elapsedSeconds: secs, startCue: .countdown)
                            },
                            onSkip: { secs in
                                WorkoutCues.cancelPendingSounds()
                                finishWarmup(elapsedSeconds: secs, startCue: .single)
                            })
    }

    func finishWarmup(elapsedSeconds secs: Int, startCue: WorkoutStartCue) {
        // Start the workout first. RootTabView keeps the warm-up surface above
        // the tabs while the root workout cover slides over it, so Home is
        // never visible between the two phases.
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            launch(.strength, startCue: startCue)
            // Record the actual warm-up time on the session just created
            // (feedback batch 6).
            active.strengthSession?.warmupSeconds = Double(secs)
            try? context.save()
        }
        if active.strengthSession != nil {
            // Keep the immersive phase up until the cover has fully covered
            // the screen, then remove it underneath the workout.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                warmupCover.dismiss()
            }
        } else {
            // Start failed (e.g. a workout conflict); reveal Home immediately
            // so the conflict alert is visible.
            warmupCover.dismiss()
        }
    }
}
