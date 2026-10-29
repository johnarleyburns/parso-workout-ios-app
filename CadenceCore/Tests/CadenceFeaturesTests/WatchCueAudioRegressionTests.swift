import Foundation
import Testing
@testable import CadenceFeatures

@MainActor
struct WatchCueAudioRegressionTests {
    @Test func speechFinishCannotDeactivateOverlappingBell() {
        let f = WatchCueAudioFixture()
        let speech = f.speak("s", owner: f.ownerA)!
        let bell = f.bell(owner: f.ownerB)!
        f.speechDriver.emit(.finished(speech))
        #expect(f.session.events == [.configureMixing, .activate])
        #expect(f.audio.activeLeaseCount == 1)
        f.bellDriver.emit(.finished(bell))
        #expect(f.session.events == [.configureMixing, .activate, .deactivateNotify])
    }

    @Test func bellFinishCannotDeactivateOverlappingSpeech() {
        let f = WatchCueAudioFixture()
        let bell = f.bell(owner: f.ownerB)!
        let speech = f.speak("s", owner: f.ownerA)!
        f.bellDriver.emit(.finished(bell))
        #expect(f.audio.activeLeaseCount == 1)
        f.speechDriver.emit(.finished(speech))
        #expect(f.audio.activeLeaseCount == 0)
        #expect(f.session.events.filter { $0 == .deactivateNotify }.count == 1)
    }

    @Test func fullWorkoutTrace() {
        let f = WatchCueAudioFixture()
        // spoken on, sounds off: speech-only cue
        let a = f.speak("A", owner: f.ownerA)!
        f.speechDriver.emit(.started(a))
        f.speechDriver.emit(.finished(a))
        #expect(f.session.events == [.configureMixing, .activate, .deactivateNotify])
        f.advanceClock(60)
        #expect(f.session.events.count == 3)

        // sounds on: speech B + bell C, replace B with D
        let b = f.speak("B", owner: f.ownerA)!
        let c = f.bell(owner: f.ownerA)!
        f.bellDriver.emit(.finished(c))
        #expect(f.session.events.count == 5)
        let d = f.speak("D", owner: f.ownerA)!
        f.speechDriver.emit(.cancelled(b))
        #expect(f.session.events.count == 5)
        f.speechDriver.emit(.finished(d))
        #expect(f.session.events.count == 6)

        // rest bells, strike 1, disable sounds
        f.bells.restComplete(owner: f.ownerA, enabled: true)
        f.scheduler.advance(0)
        f.bells.cancelAllWorkoutBells()
        f.scheduler.forceRun(f.scheduler.tasks.count - 1)
        #expect(f.audio.activeLeaseCount == 0)

        // speech E, interruption, late finish ignored
        let e = f.speak("E", owner: f.ownerA)!
        f.audio.interruptionBegan()
        f.speechDriver.emit(.finished(e))
        #expect(f.speech.pendingCount == 0)
        #expect(f.speechDriver.cancelled.contains(e))
        f.audio.interruptionEnded()
        #expect(f.speechDriver.enqueued.count == 4) // no replay
        let fresh = f.speak("F", owner: f.ownerA)!
        f.speechDriver.emit(.finished(fresh))
        #expect(f.audio.activeLeaseCount == 0)
        #expect(f.session.events.last == .deactivateNotify)
    }

    @Test func bothSettingsOffNeverTouchesTheSession() {
        let f = WatchCueAudioFixture()
        f.speech.speak(eventID: "x", text: "x", owner: f.ownerA, enabled: false)
        f.bells.play(.phase, owner: f.ownerA, enabled: false)
        f.bells.restComplete(owner: f.ownerA, enabled: false)
        #expect(f.session.events.isEmpty)
    }

    @Test func mediaResetResetsSpeechDriver() {
        let f = WatchCueAudioFixture()
        _ = f.speak("a", owner: f.ownerA)
        f.audio.invalidateAll(.mediaReset)
        #expect(f.speechDriver.resets == 1)
        #expect(f.speech.pendingCount == 0)
    }
}
