import XCTest
@testable import CadenceFeatures

final class WorkoutMirrorLifecycleTests: XCTestCase {
    func testFirstAttach() {
        var l = WorkoutMirrorLifecycle()
        XCTAssertEqual(l.apply(.startRequested), .starting)
        XCTAssertEqual(l.apply(.attached), .mirrored(generation: 1))
    }

    func testReconnectReplacesAndIncrementsGeneration() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached)
        XCTAssertEqual(l.apply(.attached), .mirrored(generation: 2))
    }

    func testOldSessionDisconnectCannotClearNewer() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached); l.apply(.attached)
        XCTAssertEqual(l.apply(.disconnected(generation: 1)), .mirrored(generation: 2))
        XCTAssertEqual(l.apply(.failed(generation: 1)), .mirrored(generation: 2))
        XCTAssertEqual(l.apply(.disconnected(generation: 2)), .disconnected(generation: 2))
    }

    func testEndClearsOnlyCurrent() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached); l.apply(.attached)
        XCTAssertEqual(l.apply(.ended(generation: 1)), .mirrored(generation: 2))
        XCTAssertEqual(l.apply(.ended(generation: 2)), .inactive)
    }

    func testMirrorFailureStillStartsPrimary() {
        XCTAssertTrue(WorkoutMirrorLifecycle.shouldStartPrimary(mirrorSucceeded: false))
    }

    // MARK: - .disconnected is recoverable, not terminal

    func testEndedAfterDisconnectTransitionsToInactiveInsteadOfStrandingState() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached) // .mirrored(1)
        XCTAssertEqual(l.apply(.disconnected(generation: 1)), .disconnected(generation: 1))
        // A genuine session-end arriving after the disconnect must not strand
        // the reducer in .disconnected forever.
        XCTAssertEqual(l.apply(.ended(generation: 1)), .inactive)
    }

    func testFailedAfterDisconnectTransitionsToInactiveInsteadOfStrandingState() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached) // .mirrored(1)
        l.apply(.disconnected(generation: 1))
        XCTAssertEqual(l.apply(.failed(generation: 1)), .inactive)
    }

    func testStaleEndedOrFailedWhileDisconnectedDoesNotClearNewerGeneration() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached); l.apply(.attached) // .mirrored(2)
        l.apply(.disconnected(generation: 2)) // .disconnected(2)
        // A stale generation-1 end/fail arriving late must not touch the
        // current generation-2 disconnected state.
        XCTAssertEqual(l.apply(.ended(generation: 1)), .disconnected(generation: 2))
        XCTAssertEqual(l.apply(.failed(generation: 1)), .disconnected(generation: 2))
    }

    // MARK: - Reconnect after disconnect

    func testReconnectAfterDisconnectProducesNewMirroredGeneration() {
        var l = WorkoutMirrorLifecycle()
        l.apply(.attached) // .mirrored(1)
        XCTAssertEqual(l.apply(.disconnected(generation: 1)), .disconnected(generation: 1))
        // HealthKit supplies a replacement mirrored session on reconnect.
        XCTAssertEqual(l.apply(.attached), .mirrored(generation: 2))
    }

    // MARK: - shouldForwardData

    func testShouldForwardDataOnlyTrueForCurrentMirroredGeneration() {
        var l = WorkoutMirrorLifecycle()
        XCTAssertFalse(l.shouldForwardData(generation: 1)) // .inactive

        l.apply(.startRequested)
        XCTAssertFalse(l.shouldForwardData(generation: 1)) // .starting

        l.apply(.attached) // .mirrored(1)
        XCTAssertTrue(l.shouldForwardData(generation: 1))
        XCTAssertFalse(l.shouldForwardData(generation: 2)) // wrong generation

        l.apply(.attached) // reconnect: .mirrored(2)
        XCTAssertFalse(l.shouldForwardData(generation: 1)) // stale/old generation
        XCTAssertTrue(l.shouldForwardData(generation: 2))

        l.apply(.disconnected(generation: 2)) // .disconnected(2)
        XCTAssertFalse(l.shouldForwardData(generation: 2)) // not mirrored anymore
    }
}
