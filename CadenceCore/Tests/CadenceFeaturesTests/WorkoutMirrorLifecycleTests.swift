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
        XCTAssertEqual(l.apply(.disconnected(generation: 2)), .disconnected)
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
}
