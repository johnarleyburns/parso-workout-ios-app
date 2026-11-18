import Testing
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// Launch-blockers Phase 1c: reference-counted keep-awake holders.
struct IdleTimerArbiterTests {

    @Test func unionOfHolders() {
        let arbiter = IdleTimerArbiter()
        var applied: [Bool] = []
        arbiter.apply = { applied.append($0) }

        arbiter.acquire("session")
        arbiter.acquire("hrGate")
        #expect(arbiter.keepAwake)
        arbiter.release("session")
        #expect(arbiter.keepAwake, "one holder remains → still awake")
        #expect(applied == [true, true, true])
    }

    @Test func lastReleaseRestores() {
        let arbiter = IdleTimerArbiter()
        var last: Bool?
        arbiter.apply = { last = $0 }
        arbiter.acquire("a")
        arbiter.acquire("b")
        arbiter.release("a")
        arbiter.release("b")
        #expect(!arbiter.keepAwake)
        #expect(last == false)
    }

    @Test func reassertMatchesHolders() {
        let arbiter = IdleTimerArbiter()
        arbiter.acquire("session")
        // The OS may have reset the idle timer while backgrounded; reassert
        // pushes the current union again on foregrounding.
        var last: Bool?
        arbiter.apply = { last = $0 }
        arbiter.reassert()
        #expect(last == true)

        arbiter.release("session")
        last = nil
        arbiter.reassert()
        #expect(last == false)
    }

    @Test func duplicateAcquireIsIdempotentPerToken() {
        let arbiter = IdleTimerArbiter()
        arbiter.acquire("x")
        arbiter.acquire("x")
        arbiter.release("x")
        #expect(!arbiter.keepAwake)
    }
}
