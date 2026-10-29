import Foundation
import Testing
@testable import CadenceFeatures

@MainActor
struct WatchCueSpeechControllerTests {
    @Test func speechOnlyCueAcquiresBeforeEnqueueAndFinishReleasesOnce() {
        let f = WatchCueAudioFixture()
        let id = f.speak("a", owner: f.ownerA)!
        #expect(f.session.events == [.configureMixing, .activate])
        f.speechDriver.emit(.started(id))
        f.speechDriver.emit(.finished(id))
        f.speechDriver.emit(.finished(id))
        #expect(f.session.events == [.configureMixing, .activate, .deactivateNotify])
        #expect(f.audio.activeLeaseCount == 0)
    }

    @Test func replacementKeepsSessionAndLateCancelCannotReleaseNewLease() {
        let f = WatchCueAudioFixture()
        let a = f.speak("a", owner: f.ownerA)!
        f.advanceClock(2)
        let b = f.speak("b", owner: f.ownerA)!
        #expect(f.speechDriver.cancelled == [a])
        f.speechDriver.emit(.started(b))
        f.speechDriver.emit(.cancelled(a))
        f.speechDriver.emit(.finished(a))
        #expect(f.audio.activeLeaseCount == 1)
        #expect(f.session.events == [.configureMixing, .activate])
        f.speechDriver.emit(.finished(b))
        #expect(f.session.events == [.configureMixing, .activate, .deactivateNotify])
    }

    @Test func queuedUtteranceWithoutCallbackIsSettledByStopAndWatchdog() {
        let f = WatchCueAudioFixture()
        _ = f.speak("a", owner: f.ownerA)
        f.speech.stop(owner: f.ownerA)
        #expect(f.audio.activeLeaseCount == 0)

        let w = f.speak("w", owner: f.ownerA)!
        f.advanceClock(11)
        #expect(f.speechDriver.cancelled.contains(w))
        #expect(f.speech.pendingCount == 0)
        let later = f.speak("w", owner: f.ownerA) // same event may retry after start failure
        #expect(later != nil)
    }

    @Test func startedUtteranceIsNotCutOffByWatchdog() {
        let f = WatchCueAudioFixture()
        let id = f.speak("long", owner: f.ownerA)!
        f.speechDriver.emit(.started(id))
        f.advanceClock(120)
        #expect(f.speech.pendingCount == 1)
        #expect(f.speechDriver.cancelled.isEmpty)
    }

    @Test func activationFailureAllowsRetryOfSameEvent() {
        let f = WatchCueAudioFixture()
        f.session.activateError = WatchCueSessionError.failed(domain: "x", code: 1)
        #expect(f.speak("a", owner: f.ownerA) == nil)
        f.session.activateError = nil
        #expect(f.speak("a", owner: f.ownerA) != nil)
    }

    @Test func dedupAndDisabledSettings() {
        let f = WatchCueAudioFixture()
        #expect(f.speak("a", owner: f.ownerA, enabled: false) == nil)
        #expect(f.session.events.isEmpty)
        let id = f.speak("a", owner: f.ownerA)!
        f.speechDriver.emit(.finished(id))
        #expect(f.speak("a", owner: f.ownerA) == nil)
        f.advanceClock(2)
        #expect(f.speak("a", owner: f.ownerA) != nil)
    }

    @Test func ownerStopLeavesOtherOwnersAlone() {
        let f = WatchCueAudioFixture()
        _ = f.speak("a", owner: f.ownerA)
        f.speech.stop(owner: f.ownerB)
        #expect(f.speech.pendingCount == 1)
    }

    @Test func disablingSpeechCancelsActiveAndQueued() {
        let f = WatchCueAudioFixture()
        _ = f.speak("a", owner: f.ownerA)
        f.speech.cancelAllWorkoutSpeech()
        #expect(f.speech.pendingCount == 0)
        #expect(f.audio.activeLeaseCount == 0)
    }
}
