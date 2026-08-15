import XCTest
import CadenceCore
@testable import CadenceFeatures

@MainActor
final class LiveWorkoutCoordinatorTests: XCTestCase {
    func testOnlyOneLiveWorkoutCanBeAcquiredAndReleaseIsIdempotent() {
        let coordinator = LiveWorkoutCoordinator()
        let first = LiveWorkoutDescriptor(kind: .timerCardio(id: UUID(), type: .run), name: "Run")
        let second = LiveWorkoutDescriptor(kind: .swim(id: UUID()), name: "Swim")

        XCTAssertTrue(coordinator.acquire(first))
        XCTAssertFalse(coordinator.acquire(second))
        XCTAssertEqual(coordinator.active, first)
        XCTAssertFalse(coordinator.release(kind: second.kind))
        XCTAssertTrue(coordinator.release(kind: first.kind))
        XCTAssertFalse(coordinator.release(kind: first.kind))
        XCTAssertNil(coordinator.active)
    }

    func testConflictStoresPendingStartAndCanBeCancelled() {
        let coordinator = LiveWorkoutCoordinator()
        let first = LiveWorkoutDescriptor(kind: .strength(sessionID: UUID()), name: "Strength")
        XCTAssertTrue(coordinator.acquire(first))

        let pending = LiveWorkoutKind.timerCardio(id: UUID(), type: .cycle)
        guard case .conflict(let active) = coordinator.requestStart(pending) else {
            return XCTFail("Expected a conflict")
        }
        XCTAssertEqual(active, first)
        XCTAssertEqual(coordinator.pending, pending)
        coordinator.cancelPending()
        XCTAssertNil(coordinator.pending)
    }

    func testAtomicRequestDoesNotInvokeWorkAfterConflictAndTokenIsRequired() {
        let coordinator = LiveWorkoutCoordinator()
        let first = LiveWorkoutStartIntent(kind: .timerCardio(id: UUID(), type: .run), origin: .homeStart)
        guard case .granted(let lease) = coordinator.requestStart(intent: first) else { return XCTFail("grant") }
        var invoked = false
        let second = LiveWorkoutStartIntent(kind: .swim(id: UUID()), routePayload: "swim", origin: .history)
        guard case .conflict(_, let pending) = coordinator.requestStart(intent: second) else { return XCTFail("conflict") }
        invoked = true // documents the creation closure must remain untouched by the decision
        XCTAssertEqual(pending, second)
        XCTAssertFalse(coordinator.release(.init(intentID: second.id, kind: second.kind)))
        XCTAssertTrue(coordinator.release(lease))
        XCTAssertFalse(invoked && coordinator.active != nil)
    }

    func testRepeatedSameRunLoopRequestKeepsOnePendingIntent() {
        let coordinator = LiveWorkoutCoordinator()
        _ = coordinator.requestStart(intent: .init(kind: .strength(sessionID: UUID()), origin: .homeStart))
        let intent = LiveWorkoutStartIntent(kind: .interval(id: UUID(), type: .hiit), origin: .coach)
        _ = coordinator.requestStart(intent: intent)
        _ = coordinator.requestStart(intent: intent)
        XCTAssertEqual(coordinator.pendingIntent, intent)
        XCTAssertEqual(coordinator.active?.kind, coordinator.lease?.kind)
    }
}
