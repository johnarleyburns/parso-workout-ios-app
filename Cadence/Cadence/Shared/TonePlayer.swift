import AVFoundation
import CadenceCore

/// Plays short sine-wave cue tones via `AVAudioPlayer`. Uses `AVAudioPlayer`
/// (not `AVAudioEngine`) on purpose: the engine's output unit interrupts the
/// user's background audio even when the session is `.playback` + `.mixWithOthers`,
/// whereas `AVAudioPlayer` mixes cleanly (matches the bundled bell players).
/// Tones are pre-rendered once to in-memory WAV data by `ToneWAV`.
@MainActor
enum TonePlayer {
    private static var sequenceToken = 0

    private static let tick: AVAudioPlayer? = makePlayer(
        ToneWAV.sine(frequency: 1047, duration: 0.04, amplitude: 0.15))
    private static let alert: AVAudioPlayer? = makePlayer(
        ToneWAV.sine(frequency: 1760, duration: 0.12, amplitude: 0.25))

    private static func makePlayer(_ data: Data) -> AVAudioPlayer? {
        let player = try? AVAudioPlayer(data: data)
        player?.prepareToPlay()
        return player
    }

    /// Soft low tick — used for phase transitions and countdown sequences.
    static func playTick() {
        WorkoutAudioSession.configureForCues()
        tick?.currentTime = 0
        tick?.play()
    }

    /// Short higher-pitched alert — used for 30 s warning and start/end.
    static func playAlert() {
        WorkoutAudioSession.configureForCues()
        alert?.currentTime = 0
        alert?.play()
    }

    /// 3 countdown ticks (1 s apart) followed by a start alert.
    static func countdownStart() {
        sequenceToken += 1
        let token = sequenceToken
        playTick()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard token == sequenceToken else { return }
            playTick()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard token == sequenceToken else { return }
            playTick()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard token == sequenceToken else { return }
            playAlert()
            Haptics.restComplete()
        }
    }

    /// A single start alert, used when the workout begins immediately.
    static func singleStart() {
        cancelPending()
        playAlert()
        Haptics.restComplete()
    }

    /// 3 rapid ticks (0.15 s apart).
    static func rapidEnd() {
        sequenceToken += 1
        let token = sequenceToken
        playTick()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard token == sequenceToken else { return }
            playTick()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            guard token == sequenceToken else { return }
            playTick()
            Haptics.restComplete()
        }
    }

    static func cancelPending() {
        sequenceToken += 1
        tick?.stop()
        alert?.stop()
    }
}
