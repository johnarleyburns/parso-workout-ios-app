import XCTest
@testable import CadenceCore

final class MuscleMapLayoutTests: XCTestCase {
    func testSourceIsSplitIntoTwoAspectPreservingHalves() {
        XCTAssertEqual(MuscleMapLayout.panelRatio,
                       MuscleMapLayout.panelPixelWidth / MuscleMapLayout.panelPixelHeight,
                       accuracy: 0.0001)
        XCTAssertGreaterThan(MuscleMapLayout.panelRatio, 0)
        XCTAssertLessThan(MuscleMapLayout.panelRatio, 1)
        XCTAssertEqual(MuscleMapLayout.panelPixelWidth, 1024, accuracy: 0.0001)
        XCTAssertEqual(MuscleMapLayout.panelPixelHeight, 1782, accuracy: 0.0001)
    }

    func testEveryAnchorStaysInsideItsAssignedHalf() {
        for callout in MuscleMapLayout.callouts {
            XCTAssertTrue((0...1).contains(callout.anchorX), callout.id)
            XCTAssertTrue((0...1).contains(callout.anchorY), callout.id)
            switch callout.side {
            case .left:
                XCTAssertLessThan(callout.anchorX, 0.5, callout.id)
            case .right:
                XCTAssertGreaterThan(callout.anchorX, 0.5, callout.id)
            }
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
