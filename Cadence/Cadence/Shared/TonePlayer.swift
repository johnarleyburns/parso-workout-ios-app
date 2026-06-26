import AVFoundation

/// Plays short sine-wave tones via AVAudioEngine so interval and workout cues
/// can fire in the background (requires `audio` background mode + `.playback`
/// category). Replaces `AudioServicesPlaySystemSound` which does not reliably
/// play when the app is backgrounded.
@MainActor
enum TonePlayer {
    private static let engine = AVAudioEngine()
    private static let playerNode = AVAudioPlayerNode()
    private static var configured = false

    /// Soft low tick — used for phase transitions and countdown sequences.
    /// ~1047 Hz (C6), 0.04 s, low volume.
    static func playTick() {
        play(frequency: 1047, duration: 0.04, amplitude: 0.15)
    }

    /// Short higher-pitched alert — used for 30 s warning and start/end.
    /// ~1760 Hz (A6), 0.12 s, moderate volume.
    static func playAlert() {
        play(frequency: 1760, duration: 0.12, amplitude: 0.25)
    }

    /// 3 countdown ticks (1 s apart) followed by a start alert.
    static func countdownStart() {
        playTick()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { playTick() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { playTick() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            playAlert()
            Haptics.restComplete()
        }
    }

    /// 3 rapid ticks (0.15 s apart).
    static func rapidEnd() {
        playTick()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { playTick() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            playTick()
            Haptics.restComplete()
        }
    }

    // MARK: - Engine plumbing

    private static func play(frequency: Double, duration: Double, amplitude: Double) {
        configureIfNeeded()

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        let sampleCount = Int(duration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else { return }

        buffer.frameLength = buffer.frameCapacity

        let channelCount = Int(format.channelCount)
        for ch in 0 ..< channelCount {
            guard let data = buffer.floatChannelData?[ch] else { continue }
            for i in 0 ..< sampleCount {
                let t = Double(i) / sampleRate
                // Gentle attack/decay envelope to avoid clicks
                let envelope = min(t / 0.005, 1.0, (duration - t) / 0.005, 1.0)
                data[i] = Float(amplitude * envelope * sin(2 * .pi * frequency * t))
            }
        }

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private static func configureIfNeeded() {
        guard !configured else { return }
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        try? engine.start()
        configured = true
    }
}
