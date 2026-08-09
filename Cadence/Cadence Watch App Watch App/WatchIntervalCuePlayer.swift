import AVFoundation
import CadenceFeatures
import Foundation

@MainActor
final class WatchIntervalCuePlayer {
    private let bell = WatchIntervalCuePlayer.player(named: "opening-closing-bell")
    private let warningBell = WatchIntervalCuePlayer.player(named: "warning-bell")
    private let audioSession: WatchWorkoutAudioSession
    private var sequenceToken = 0

    init() {
        self.audioSession = .shared
    }

    init(audioSession: WatchWorkoutAudioSession) {
        self.audioSession = audioSession
    }

    func phaseTransition(soundsEnabled: Bool, isBoxing: Bool) {
        guard soundsEnabled else { return }
        play(bell)
    }

    func warning(soundsEnabled: Bool, isBoxing: Bool) {
        guard soundsEnabled, isBoxing else { return }
        play(warningBell)
    }

    /// Three clear bells when a strength rest timer reaches zero.
    func restComplete(soundsEnabled: Bool) {
        guard soundsEnabled else { return }
        sequenceToken += 1
        let token = sequenceToken
        for offset in WatchWorkoutCuePolicy.restCompletionBellOffsets {
            DispatchQueue.main.asyncAfter(deadline: .now() + offset) { [weak self] in
                guard let self, token == self.sequenceToken else { return }
                self.play(self.warningBell)
            }
        }
    }

    func stop() {
        sequenceToken += 1
        bell?.stop()
        warningBell?.stop()
        audioSession.deactivate()
    }

    private static func player(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }

    private func play(_ player: AVAudioPlayer?) {
        audioSession.activateForCues()
        player?.currentTime = 0
        player?.play()
    }
}
