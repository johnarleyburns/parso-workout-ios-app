import CadenceFeatures
import Foundation

/// Bell cues for one view/workout owner. Playback lifetime is driven by completion
/// callbacks inside `WatchCueBellController`; this type never touches the audio session.
@MainActor
final class WatchIntervalCuePlayer {
    let owner: UUID
    private let bells: WatchCueBellController

    init(owner: UUID = UUID(), bells: WatchCueBellController = WatchCueAudioHub.shared.bells) {
        self.owner = owner
        self.bells = bells
    }

    func phaseTransition(soundsEnabled: Bool, isBoxing: Bool) {
        bells.play(.phase, owner: owner, enabled: soundsEnabled)
    }

    func warning(soundsEnabled: Bool, isBoxing: Bool) {
        bells.play(.warning, owner: owner, enabled: soundsEnabled && isBoxing)
    }

    /// Three clear bells when a strength rest timer reaches zero.
    func restComplete(soundsEnabled: Bool) {
        bells.restComplete(owner: owner, enabled: soundsEnabled)
    }

    func stop() {
        bells.stop(owner: owner)
    }
}
