import AVFoundation
import Foundation

final class WatchIntervalCuePlayer {
    private let bell = WatchIntervalCuePlayer.player(named: "opening-closing-bell")
    private let warningBell = WatchIntervalCuePlayer.player(named: "warning-bell")
    private var sessionActive = false

    func phaseTransition(soundsEnabled: Bool, isBoxing: Bool) {
        guard soundsEnabled else { return }
        play(bell)
    }

    func warning(soundsEnabled: Bool, isBoxing: Bool) {
        guard soundsEnabled, isBoxing else { return }
        play(warningBell)
    }

    func stop() {
        bell?.stop()
        warningBell?.stop()
        deactivateSession()
    }

    private static func player(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }

    private func play(_ player: AVAudioPlayer?) {
        activateSession()
        player?.currentTime = 0
        player?.play()
    }

    private func activateSession() {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        sessionActive = true
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false)
        sessionActive = false
    }
}
