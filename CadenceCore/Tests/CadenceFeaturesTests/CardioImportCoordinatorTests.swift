import Foundation
import Testing
import CadenceCore
import CadenceFixtures
@testable import CadenceFeatures

@MainActor
struct CardioImportCoordinatorTests {
    private struct Boom: Error {}

    private func make(_ fake: FakeHealthProvider,
                      persist: @escaping CardioImportCoordinator.Persist = { CardioImportReport(inserted: $0.upserts.count, removed: 0) },
                      committed: @escaping (CardioImportReport) -> Void = { _ in }) -> CardioImportCoordinator {
        CardioImportCoordinator(provider: fake, persist: persist, onCommittedChange: committed)
    }

    @Test func concurrentTriggersSerializeAndNeverOverlap() async {
        let fake = FakeHealthProvider()
        var inFlight = 0, maxInFlight = 0
        let c = make(fake, persist: { delta in
            inFlight += 1; maxInFlight = max(maxInFlight, inFlight)
            for _ in 0..<20 { await Task.yield() }
            inFlight -= 1
            return CardioImportReport(inserted: delta.upserts.count, removed: 0)
        })
        let first = Task { @MainActor in await c.request(.foreground) }
        while !c.isRunning { await Task.yield() }
        async let b = c.request(.observer)
        async let m = c.request(.manualRefresh)
        _ = await (first.value, b, m)
        #expect(maxInFlight == 1)
        #expect(c.passCount == 2) // first run plus exactly one coalesced follow-up
        #expect(!c.isRunning)
    }

    @Test func observerCompletionFiresExactlyOnceOnEveryPath() async {
        for mode in 0..<3 {
            let fake = FakeHealthProvider()
            if mode == 1 { fake.importFetchError = Boom() }
            let c = make(fake, persist: { d in
                if mode == 2 { throw CancellationError() }
                return CardioImportReport(inserted: d.upserts.count, removed: 0)
            })
            var count = 0
            let completion = HealthObserverCompletion { count += 1 }
            await c.handleObserverDelivery(completion)
            completion.finish()
            #expect(count == 1)
        }
    }

    @Test func failureStaysRetryableAndLaterTriggerSucceeds() async {
        let fake = FakeHealthProvider()
        fake.importFetchError = Boom()
        let c = make(fake)
        let failed = await c.request(.observer)
        guard case .failed = failed else { Issue.record("expected failure"); return }
        #expect(fake.committedAnchors.isEmpty)
        fake.importFetchError = nil
        let ok = await c.request(.foreground)
        guard case .completed(_, let report) = ok else { Issue.record("expected success"); return }
        #expect(report.inserted == 1)
        #expect(fake.committedAnchors.count == 1)
    }

    @Test func committedChangeNotifiesOnceAndNoChangeDoesNot() async {
        let fake = FakeHealthProvider()
        var notified = 0
        let c = make(fake, committed: { _ in notified += 1 })
        await c.request(.homeDisplay)
        #expect(notified == 1)
        fake.pendingWorkouts = []
        await c.request(.manualRefresh)
        #expect(notified == 1)
        guard case .completed(_, let report) = c.state else { Issue.record("expected completed"); return }
        #expect(!report.changedHistory) // empty read is a success, not an error
    }

    @Test func failedPersistDoesNotCommitOrNotify() async {
        let fake = FakeHealthProvider()
        var notified = 0
        let c = make(fake, persist: { _ in throw Boom() }, committed: { _ in notified += 1 })
        await c.request(.observer)
        #expect(fake.committedAnchors.isEmpty)
        #expect(notified == 0)
    }
}
