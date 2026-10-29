import AVFoundation
import CadenceCore
import CadenceFeatures
import Observation

/// Production composition root: one coordinator shared by speech and every bell player.
@MainActor
final class WatchCueAudioHub {
    static let shared = WatchCueAudioHub()

    let audio: WatchCueAudioCoordinator
    let speech: WatchCueSpeechController
    let bells: WatchCueBellController
    private var observers: [NSObjectProtocol] = []
    private var observedSettings: AppSettings?

    private init() {
        let scheduler = WatchCueTaskScheduler()
        audio = WatchCueAudioCoordinator(driver: WatchWorkoutAudioSession(), scheduler: scheduler)
        speech = WatchCueSpeechController(audio: audio, driver: WatchAVSpeechDriver(), scheduler: scheduler)
        bells = WatchCueBellController(audio: audio, driver: WatchAVBellDriver(), scheduler: scheduler)
        observeSession()
    }

    /// Cancels a category when the user turns it off, whether locally or via phone sync.
    func observeSettings(_ settings: AppSettings) {
        observedSettings = settings
        trackSettings()
    }

    private func trackSettings() {
        guard let settings = observedSettings else { return }
        withObservationTracking {
            _ = settings.spokenCues
            _ = settings.workoutSounds
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, let settings = self.observedSettings else { return }
                if !settings.spokenCues { self.speech.cancelAllWorkoutSpeech() }
                if !settings.workoutSounds { self.bells.cancelAllWorkoutBells() }
                self.trackSettings()
            }
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        let audio = audio
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: nil, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = raw == AVAudioSession.InterruptionType.began.rawValue
            Task { @MainActor in
                if began { audio.interruptionBegan() } else { audio.interruptionEnded() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                            object: nil, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in audio.invalidateAll(.routeLoss) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                            object: nil, queue: .main) { _ in
            Task { @MainActor in audio.invalidateAll(.mediaReset) }
        })
    }
}
