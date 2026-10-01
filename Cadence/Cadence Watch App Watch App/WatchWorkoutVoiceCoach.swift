import AVFoundation
import CadenceCore
import CadenceFeatures

/// Short, interruptible workout announcements spoken by the Watch. The
/// workout audio session lets watchOS route these cues to connected Bluetooth
/// headphones when they are the active route.
@MainActor
final class WatchWorkoutVoiceCoach {
    static let shared = WatchWorkoutVoiceCoach()

    private let synthesizer = AVSpeechSynthesizer()
    private let audioSession: WatchWorkoutAudioSession
    private var lastEventID: String?
    private var lastSpokenAt = Date.distantPast

    init(audioSession: WatchWorkoutAudioSession = .shared) {
        self.audioSession = audioSession
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ cue: WatchVoiceCue, enabled: Bool) {
        guard enabled else { return }
        let now = Date()
        // TimelineView can deliver the same boundary more than once.
        guard cue.eventID != lastEventID || now.timeIntervalSince(lastSpokenAt) > 1 else { return }
        lastEventID = cue.eventID
        lastSpokenAt = now
        audioSession.activateForCues()
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: cue.speechText)
        utterance.rate = 0.48
        utterance.volume = 1
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier
                                                  ?? "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        audioSession.deactivate()
        lastEventID = nil
    }
}
