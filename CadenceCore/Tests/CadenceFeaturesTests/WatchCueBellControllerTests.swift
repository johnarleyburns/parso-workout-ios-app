import Foundation
import Testing
@testable import CadenceFeatures

@MainActor
struct WatchCueBellControllerTests {
    @Test func bellMixesAndNaturalFinishReturnsIdle() {
        let f = WatchCueAudioFixture()
        let id = f.bell(owner: f.ownerA)!
        #expect(f.session.events == [.configureMixing, .activate])
        f.bellDriver.emit(.finished(id))
        #expect(f.session.events.last == .deactivateNotify)
        #expect(f.bells.playingCount == 0)
    }

    @Test func missingAssetNeverActivatesLeaseLeaksNothing() {
        let f = WatchCueAudioFixture()
        f.bellDriver.assetAvailable = false
        #expect(f.bell(owner: f.ownerA) == nil)
        #expect(f.audio.activeLeaseCount == 0)
        #expect(f.bells.playingCount == 0)
    }

    @Test func twoOwnersOverlapWithoutEarlyDeactivation() {
        let f = WatchCueAudioFixture()
        let a = f.bell(owner: f.ownerA)!
        let b = f.bell(owner: f.ownerB)!
        f.bells.stop(owner: f.ownerA)
        #expect(f.bellDriver.stopped == [a])
        f.bellDriver.emit(.finished(a))
        #expect(!f.session.events.contains(.deactivateNotify))
        f.bellDriver.emit(.finished(b))
        #expect(f.session.events.last == .deactivateNotify)
    }

    @Test func restCompleteUsesPolicyOffsetsAndPlaysThreeFullStrikes() {
        let f = WatchCueAudioFixture()
        f.bells.restComplete(owner: f.ownerA, enabled: true)
        #expect(f.scheduler.scheduledOffsets == [0, 0.85, 1.70])
        f.scheduler.advance(0)
        f.scheduler.advance(0.85)
        f.scheduler.advance(0.85)
        #expect(f.bellDriver.started.count == 3)
        for id in f.bellDriver.started { f.bellDriver.emit(.finished(id)) }
        #expect(f.audio.activeLeaseCount == 0)
        #expect(f.session.events.filter { $0 == .activate }.count == 1)
    }

    @Test func stopBetweenStrikesAndStaleClosureStartNothing() {
        let f = WatchCueAudioFixture()
        f.bells.restComplete(owner: f.ownerA, enabled: true)
        f.scheduler.advance(0)
        f.bells.stop(owner: f.ownerA)
        f.scheduler.forceRun(1)
        f.scheduler.forceRun(2)
        #expect(f.bellDriver.started.count == 1)
        #expect(f.audio.activeLeaseCount == 0)
        // a new sequence is unaffected by old work
        f.bells.restComplete(owner: f.ownerA, enabled: true)
        f.scheduler.forceRun(1)
        #expect(f.bellDriver.started.count == 1)
    }
}
