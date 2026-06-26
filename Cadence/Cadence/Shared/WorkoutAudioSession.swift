import Foundation
import AVFoundation

/// The single source of truth for how Cladiron's workout cues touch the system
/// audio session. Every beep, bell, and spoken cue routes through here so the
/// app can never pause or duck the user's background audio (music, podcast,
/// nav voice). Centralizing it means future cue code cannot reintroduce ducking.
///
/// We use `.playback` + `.mixWithOthers`: cues are eligible for background audio
/// (required for interval bells/beeps when the device is locked) and mix with
/// other audio without interrupting it. `.duckOthers` is intentionally never
/// requested — the user's priority is non-interference, not making the cue the
/// loudest sound.
@MainActor
enum WorkoutAudioSession {
    /// Configure (once, idempotently) for non-interrupting cue playback. Safe to
    /// call before every cue; `setCategory`/`setActive` are cheap no-ops when the
    /// session is already in this configuration.
    static func configureForCues() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
    }

    static func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
