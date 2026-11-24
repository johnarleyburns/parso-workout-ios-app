import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Large live-HR readout for the guided warm-up. Warm-up is primarily a cardio
/// task, so it uses the same big BPM treatment as the cardio screens while the
/// countdown drops to a secondary line.
struct GuidedPhaseLiveHRView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    var idPrefix: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { context in
            let fresh = model.hrm.source != .appleWatch
                || model.watchHRConnection.isSampleFresh(now: context.date)
            let bpm = fresh ? model.hrm.currentBPM : nil
            let profile = model.currentIntensityProfile()
            let maxHR = profile.maximumHR ?? CardioMath.defaultMaxHR(age: settings.userAge)
            let zone = bpm.map { CardioMath.hrZone(bpm: $0, maxHR: maxHR) } ?? 0
            LiveHRBigView(
                bpm: bpm,
                zone: zone,
                avgHR: nil,
                idPrefix: idPrefix,
                intensityProfile: profile,
                // Warm-up/cool-down are guided phases, not connection setup:
                // never show "Reconnecting…" or a reconnect action here.
                connectionNote: nil)
        }
    }
}
