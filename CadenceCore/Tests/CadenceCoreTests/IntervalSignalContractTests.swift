import XCTest
@testable import CadenceCore

final class IntervalSignalContractTests: XCTestCase {
    func testWarningDurationTable() {
        let cases: [(TimeInterval, TimeInterval)] = [(20, 5), (30, 5), (45, 10), (60, 10),
                                                      (90, 15), (120, 20), (180, 30), (300, 50)]
        for (duration, expected) in cases {
            XCTAssertEqual(IntervalSignal.warningDuration(forWorkDuration: duration), expected, accuracy: 0.001)
        }
    }

    func testBoundaryAndEpsilon() {
        XCTAssertEqual(IntervalSignal.colorState(phase: .work, remaining: 10, phaseDuration: 60), .warning)
        XCTAssertEqual(IntervalSignal.colorState(phase: .work, remaining: 10.001, phaseDuration: 60), .work)
        XCTAssertEqual(IntervalSignal.colorState(phase: .work, remaining: 3.001, phaseDuration: 60), .warning)
        XCTAssertEqual(IntervalSignal.colorState(phase: .work, remaining: 3, phaseDuration: 60), .imminent)
    }

    func testShortWorkDoesNotStayWarningForEntirePhase() {
        XCTAssertEqual(IntervalSignal.colorState(phase: .work, remaining: 19, phaseDuration: 20), .work)
        XCTAssertEqual(IntervalSignal.colorState(phase: .work, remaining: 5, phaseDuration: 20), .warning)
        XCTAssertEqual(IntervalSignal.colorState(phase: .work, remaining: 3, phaseDuration: 20), .imminent)
    }
}
