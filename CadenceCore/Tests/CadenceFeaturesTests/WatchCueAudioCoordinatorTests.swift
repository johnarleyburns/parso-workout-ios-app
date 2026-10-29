import Foundation
import Testing
@testable import CadenceFeatures

@MainActor
struct WatchCueAudioCoordinatorTests {
    @Test func firstLeaseConfiguresOnceAndLastReleaseDeactivates() throws {
        let f = WatchCueAudioFixture()
        let a = try f.audio.acquire(owner: f.ownerA)
        let b = try f.audio.acquire(owner: f.ownerB)
        #expect(f.session.events == [.configureMixing, .activate])
        f.audio.release(a)
        f.audio.release(a) // double release is harmless
        #expect(f.session.events == [.configureMixing, .activate])
        f.audio.release(b)
        #expect(f.session.events == [.configureMixing, .activate, .deactivateNotify])
        #expect(f.audio.activeLeaseCount == 0)
    }

    @Test func activationFailureIssuesNoLeaseAndNextCueRecovers() throws {
        let f = WatchCueAudioFixture()
        f.session.activateError = WatchCueSessionError.failed(domain: "x", code: 1)
        #expect(throws: WatchCueSessionError.self) { try f.audio.acquire(owner: f.ownerA) }
        #expect(f.audio.activeLeaseCount == 0)
        #expect(f.audio.state == .uncertain)
        f.session.activateError = nil
        _ = try f.audio.acquire(owner: f.ownerA)
        #expect(f.audio.state == .active)
    }

    @Test func busyDeactivationCountsAsReleasedOtherErrorsAreUncertainWithBoundedRetry() throws {
        let f = WatchCueAudioFixture()
        f.session.deactivateErrors = [WatchCueSessionError.busy]
        f.audio.release(try f.audio.acquire(owner: f.ownerA))
        #expect(f.audio.state == .inactive)

        f.session.deactivateErrors = [WatchCueSessionError.failed(domain: "x", code: 2),
                                      WatchCueSessionError.failed(domain: "x", code: 2)]
        f.audio.release(try f.audio.acquire(owner: f.ownerA))
        #expect(f.audio.state == .uncertain)
        f.scheduler.advance(5)
        // one retry only, no polling loop
        f.scheduler.advance(600)
        let deactivations = f.session.events.filter { $0 == .deactivateNotify }.count
        #expect(deactivations == 3)
    }

    @Test func newerAcquireCancelsStaleRetry() throws {
        let f = WatchCueAudioFixture()
        f.session.deactivateErrors = [WatchCueSessionError.failed(domain: "x", code: 2)]
        f.audio.release(try f.audio.acquire(owner: f.ownerA))
        let lease = try f.audio.acquire(owner: f.ownerB)
        f.scheduler.advance(60)
        #expect(f.audio.activeLeaseCount == 1)
        #expect(f.session.events.last != .deactivateNotify)
        f.audio.release(lease)
    }

    @Test func interruptionInvalidatesOwnersBlocksAcquireAndNeverReplays() throws {
        let f = WatchCueAudioFixture()
        let lease = try f.audio.acquire(owner: f.ownerA)
        f.audio.interruptionBegan()
        #expect(f.audio.activeLeaseCount == 0)
        #expect(throws: CueAudioError.self) { try f.audio.acquire(owner: f.ownerA) }
        f.audio.release(lease) // stale
        f.audio.interruptionEnded()
        let fresh = try f.audio.acquire(owner: f.ownerA)
        #expect(fresh.epoch > lease.epoch)
        f.audio.release(fresh)
        #expect(f.audio.activeLeaseCount == 0)
    }

    @Test func mediaResetAndRouteLossAreDistinct() throws {
        let f = WatchCueAudioFixture()
        _ = try f.audio.acquire(owner: f.ownerA)
        f.audio.invalidateAll(.mediaReset)
        #expect(f.audio.state == .inactive)
        _ = try f.audio.acquire(owner: f.ownerA)
        f.audio.invalidateAll(.routeLoss)
        #expect(f.session.events.last == .deactivateNotify)
        #expect(f.audio.activeLeaseCount == 0)
    }
}
