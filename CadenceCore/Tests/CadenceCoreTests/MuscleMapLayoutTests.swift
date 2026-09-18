import XCTest
@testable import CadenceCore

final class MuscleMapLayoutTests: XCTestCase {
    func testSourceIsSplitIntoTwoAspectPreservingHalves() {
        XCTAssertEqual(MuscleMapLayout.sourceRatio, 2 * MuscleMapLayout.halfRatio, accuracy: 0.0001)
        XCTAssertGreaterThan(MuscleMapLayout.halfRatio, 0)
        XCTAssertLessThan(MuscleMapLayout.halfRatio, 1)
    }

    func testEveryAnchorStaysInsideItsAssignedHalf() {
        for callout in MuscleMapLayout.callouts {
            XCTAssertTrue((0...1).contains(callout.anchorX), callout.id)
            XCTAssertTrue((0...1).contains(callout.anchorY), callout.id)
        }
    }

    func testCalloutsAreDeterministicAndHaveBothSides() {
        XCTAssertFalse(MuscleMapLayout.callouts(for: .front).isEmpty)
        XCTAssertFalse(MuscleMapLayout.callouts(for: .back).isEmpty)
        let ids = MuscleMapLayout.callouts.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(MuscleMapLayout.callouts,
                       MuscleMapLayout.callouts(for: .front) + MuscleMapLayout.callouts(for: .back))
    }
}
