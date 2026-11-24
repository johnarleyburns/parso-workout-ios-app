import SwiftUI
import Observation
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Owns the immersive warm-up phase at the root of the phone app. Presenting it
/// above the tabs (rather than as a child `fullScreenCover`) means the workout
/// cover can slide over it when the phase ends, so Home never flashes between
/// the two surfaces.
@Observable
final class WarmupCoverController {
    var isPresented = false
    var minutes = 5
    var soundsEnabled = true
    var onFinish: ((Int) -> Void)?
    var onSkip: ((Int) -> Void)?

    func present(minutes: Int,
                 soundsEnabled: Bool,
                 onFinish: @escaping (Int) -> Void,
                 onSkip: @escaping (Int) -> Void) {
        self.minutes = max(1, minutes)
        self.soundsEnabled = soundsEnabled
        self.onFinish = onFinish
        self.onSkip = onSkip
        isPresented = true
    }

    func dismiss() {
        isPresented = false
        onFinish = nil
        onSkip = nil
    }
}

/// The warm-up surface itself. It uses the same guided-phase timer as cool-down
/// with the cardio (live HR) emphasis.
struct WarmupPhaseCover: View {
    let controller: WarmupCoverController

    var body: some View {
        GuidedPhaseOverlay(
            title: String(localized: "Warm Up"),
            minutes: controller.minutes,
            tint: .orange,
            idPrefix: "warmup",
            soundsEnabled: controller.soundsEnabled,
            emphasis: .liveMetric,
            pauseShowsTitle: false,
            finishSystemImage: "chevron.forward.2",
            onFinish: { seconds in controller.onFinish?(seconds) },
            onSkip: { seconds in controller.onSkip?(seconds) },
            liveMetric: AnyView(GuidedPhaseLiveHRView(idPrefix: "warmup")))
            .accessibilityIdentifier("warmup.cover")
    }
}
