import CadenceFeatures
import Foundation

/// Short, interruptible workout announcements spoken by the Watch.
///
/// Thin facade over `WatchCueSpeechController`: every utterance holds a lease on the
/// shared `WatchCueAudioCoordinator` until the synthesizer reports it finished or
/// cancelled, so the session is released as soon as the last cue ends.
@MainActor
final class WatchWorkoutVoiceCoach {
    static let shared = WatchWorkoutVoiceCoach()
    /// Owner for callers that do not carry their own identity.
    static let sharedOwner = UUID()

    private let controller = WatchCueAudioHub.shared.speech

    func speak(_ cue: WatchVoiceCue, owner: UUID = WatchWorkoutVoiceCoach.sharedOwner, enabled: Bool) {
        controller.speak(cue, owner: owner, enabled: enabled)
    }

    func stop(owner: UUID = WatchWorkoutVoiceCoach.sharedOwner) {
        controller.stop(owner: owner)
    }
}
