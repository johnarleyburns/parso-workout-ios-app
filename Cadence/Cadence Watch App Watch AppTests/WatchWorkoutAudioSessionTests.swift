import AVFoundation
import CadenceFeatures
import Testing
@testable import Cadence_Watch_App_Watch_App

@MainActor
struct WatchWorkoutAudioSessionTests {
    @Test func everyCueMixesWithoutDuckingOrInterruptingBackgroundAudio() throws {
        let system = AudioSessionSpy()
        let subject = WatchWorkoutAudioSession(session: system)

        try subject.activateMixingPlayback()

        #expect(system.category == .playback)
        #expect(system.mode == .default)
        #expect(system.categoryOptions == [.mixWithOthers])
        #expect(system.activeCalls == [true])
        #expect(system.activationOptions.isEmpty)
    }

    @Test func deactivationHandsAudioBackToTheMusicApp() throws {
        let system = AudioSessionSpy()
        let subject = WatchWorkoutAudioSession(session: system)
        try subject.activateMixingPlayback()

        try subject.deactivateNotifyingOthers()

        #expect(system.activeCalls == [true, false])
        #expect(system.deactivationOptions.contains(.notifyOthersOnDeactivation))
    }

    @Test func busyIsClassifiedSeparatelyFromOtherFailures() {
        let busy = NSError(domain: NSOSStatusErrorDomain, code: AVAudioSession.ErrorCode.isBusy.rawValue)
        #expect(WatchWorkoutAudioSession.classify(busy) == .busy)
        #expect(WatchWorkoutAudioSession.classify(NSError(domain: "x", code: 3)) == .failed(domain: "x", code: 3))
    }

    @Test func speechUsesTheCoordinatedApplicationSession() {
        let driver = WatchAVSpeechDriver()
        #expect(driver.synthesizerUsesApplicationAudioSession)
    }
}

private final class AudioSessionSpy: WatchAudioSessioning {
    var category: AVAudioSession.Category?
    var mode: AVAudioSession.Mode?
    var categoryOptions: AVAudioSession.CategoryOptions = []
    var activeCalls: [Bool] = []
    var deactivationOptions: AVAudioSession.SetActiveOptions = []
    var activationOptions: AVAudioSession.SetActiveOptions = []

    func setCategory(_ category: AVAudioSession.Category,
                     mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws {
        self.category = category
        self.mode = mode
        categoryOptions = options
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        activeCalls.append(active)
        if active { activationOptions = options } else { deactivationOptions = options }
    }
}
