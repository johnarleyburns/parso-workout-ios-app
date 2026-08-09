import AVFoundation
import Testing
@testable import Cadence_Watch_App_Watch_App

@MainActor
struct WatchWorkoutAudioSessionTests {
    @Test func everyCueMixesWithoutDuckingOrInterruptingBackgroundAudio() {
        let system = AudioSessionSpy()
        let subject = WatchWorkoutAudioSession(session: system)

        subject.activateForCues()

        #expect(system.category == .playback)
        #expect(system.mode == .default)
        #expect(system.categoryOptions.contains(.mixWithOthers))
        #expect(!system.categoryOptions.contains(.duckOthers))
        #expect(system.activeCalls == [true])
        #expect(subject.isActive)
    }

    @Test func deactivationHandsAudioBackToTheMusicApp() {
        let system = AudioSessionSpy()
        let subject = WatchWorkoutAudioSession(session: system)
        subject.activateForCues()

        subject.deactivate()

        #expect(system.activeCalls == [true, false])
        #expect(system.deactivationOptions.contains(.notifyOthersOnDeactivation))
        #expect(!subject.isActive)
    }
}

private final class AudioSessionSpy: WatchAudioSessioning {
    var category: AVAudioSession.Category?
    var mode: AVAudioSession.Mode?
    var categoryOptions: AVAudioSession.CategoryOptions = []
    var activeCalls: [Bool] = []
    var deactivationOptions: AVAudioSession.SetActiveOptions = []

    func setCategory(_ category: AVAudioSession.Category,
                     mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws {
        self.category = category
        self.mode = mode
        categoryOptions = options
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        activeCalls.append(active)
        if !active { deactivationOptions = options }
    }
}
