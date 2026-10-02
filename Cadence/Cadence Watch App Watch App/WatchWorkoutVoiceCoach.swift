import AVFoundation
import CadenceCore
import CadenceFeatures

/// Short, interruptible workout announcements spoken by the Watch.
///
/// Speech uses a system-managed audio session (`usesApplicationAudioSession`
/// is false) rather than the shared workout cue session. The bell player
/// reconfigures that shared session on every beep, which can leave an
/// `AVSpeechSynthesizer` sharing it silent on watchOS. Letting the system own
/// speech keeps the cues audible and still mixes and ducks them with music.
@MainActor
final class WatchWorkoutVoiceCoach {
    static let shared = WatchWorkoutVoiceCoach()

    private let synthesizer = AVSpeechSynthesizer()
    private var lastEventID: String?
    private var lastSpokenAt = Date.distantPast

    init() {
        synthesizer.usesApplicationAudioSession = false
    }

    func speak(_ cue: WatchVoiceCue, enabled: Bool) {
        guard enabled else { return }
        let now = Date()
        // TimelineView can deliver the same boundary more than once.
        guard cue.eventID != lastEventID || now.timeIntervalSince(lastSpokenAt) > 1 else { return }
        lastEventID = cue.eventID
        lastSpokenAt = now
        // Only interrupt a cue that is actually still speaking; stopping an
        // idle synthesizer immediately before speaking drops the new utterance
        // on watchOS.
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: cue.speechText)
        utterance.rate = 0.48
        utterance.volume = 1
        if let voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US") {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        lastEventID = nil
    }
}
