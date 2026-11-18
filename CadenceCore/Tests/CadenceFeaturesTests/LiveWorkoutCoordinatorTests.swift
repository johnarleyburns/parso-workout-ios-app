import Testing
import Foundation
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

@MainActor
@Suite final class LiveWorkoutCoordinatorTests {
    @Test func onlyOneLiveWorkoutCanBeAcquiredAndReleaseIsIdempotent() {
        let coordinator = LiveWorkoutCoordinator()
        let first = LiveWorkoutDescriptor(kind: .timerCardio(id: UUID(), type: .run), name: "Run")
        let second = LiveWorkoutDescriptor(kind: .swim(id: UUID()), name: "Swim")

        #expect(coordinator.acquire(first))
        #expect(!coordinator.acquire(second))
        #expect(coordinator.active == first)
        #expect(!coordinator.release(kind: second.kind))
        #expect(coordinator.release(kind: first.kind))
        #expect(!coordinator.release(kind: first.kind))
        #expect(coordinator.active == nil)
    }

    @Test func conflictStoresPendingStartAndCanBeCancelled() {
        let coordinator = LiveWorkoutCoordinator()
        let first = LiveWorkoutDescriptor(kind: .strength(sessionID: UUID()), name: "Strength")
        #expect(coordinator.acquire(first))

        let pending = LiveWorkoutKind.timerCardio(id: UUID(), type: .cycle)
        guard case .conflict(let active) = coordinator.requestStart(pending) else {
            Issue.record("Expected a conflict")
            return
        }
        #expect(active == first)
        #expect(coordinator.pending == pending)
        coordinator.cancelPending()
        #expect(coordinator.pending == nil)
    }

    @Test func atomicRequestDoesNotInvokeWorkAfterConflictAndTokenIsRequired() {
        let coordinator = LiveWorkoutCoordinator()
        let first = LiveWorkoutStartIntent(kind: .timerCardio(id: UUID(), type: .run), origin: .homeStart)
        guard case .granted(let lease) = coordinator.requestStart(intent: first) else {
            Issue.record("grant")
            return
        }
        var invoked = false
        let second = LiveWorkoutStartIntent(kind: .swim(id: UUID()), routePayload: "swim", origin: .history)
        guard case .conflict(_, let pending) = coordinator.requestStart(intent: second) else {
            Issue.record("conflict")
            return
        }
        invoked = true // documents the creation closure must remain untouched by the decision
        #expect(pending == second)
        #expect(!coordinator.release(.init(intentID: second.id, kind: second.kind)))
        #expect(coordinator.release(lease))
        #expect(!(invoked && coordinator.active != nil))
    }

    @Test func repeatedSameRunLoopRequestKeepsOnePendingIntent() {
        let coordinator = LiveWorkoutCoordinator()
        _ = coordinator.requestStart(intent: .init(kind: .strength(sessionID: UUID()), origin: .homeStart))
        let intent = LiveWorkoutStartIntent(kind: .interval(id: UUID(), type: .hiit), origin: .coach)
        _ = coordinator.requestStart(intent: intent)
        _ = coordinator.requestStart(intent: intent)
        #expect(coordinator.pendingIntent == intent)
        #expect(coordinator.active?.kind == coordinator.lease?.kind)
    }
}
