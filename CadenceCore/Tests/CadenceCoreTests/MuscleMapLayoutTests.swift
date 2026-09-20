import XCTest
@testable import CadenceCore

final class MuscleMapLayoutTests: XCTestCase {
    func testSourceIsSplitIntoTwoAspectPreservingHalves() {
        XCTAssertEqual(MuscleMapLayout.sourceRatio, 2 * MuscleMapLayout.halfRatio, accuracy: 0.0001)
        XCTAssertEqual(MuscleMapLayout.halfWidth, MuscleMapLayout.sourceWidth / 2, accuracy: 0.0001)
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
        let front = MuscleMapLayout.callouts(for: .front)
        let back = MuscleMapLayout.callouts(for: .back)
        XCTAssertEqual(front.count, 12)
        XCTAssertEqual(back.count, 13)
        XCTAssertFalse(front.isEmpty)
        XCTAssertFalse(back.isEmpty)
        XCTAssertTrue(front.contains { $0.side == .left })
        XCTAssertTrue(front.contains { $0.side == .right })
        XCTAssertTrue(back.contains { $0.side == .left })
        XCTAssertTrue(back.contains { $0.side == .right })
        let ids = MuscleMapLayout.callouts.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(MuscleMapLayout.callouts,
                       MuscleMapLayout.callouts(for: .front) + MuscleMapLayout.callouts(for: .back))
    }
}
