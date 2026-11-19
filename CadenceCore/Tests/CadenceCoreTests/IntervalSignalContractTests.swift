import Foundation
import Testing
@testable import CadenceCore

struct IntervalSignalContractTests {
    @Test func warningDurationTable() {
        let cases: [(TimeInterval, TimeInterval)] = [(20, 5), (30, 5), (45, 10), (60, 10),
                                                      (90, 15), (120, 20), (180, 30), (300, 50)]
        for (duration, expected) in cases {
            #expect(abs(IntervalSignal.warningDuration(forWorkDuration: duration) - expected) <= 0.001)
        }
    }

    @Test func boundaryAndEpsilon() {
        #expect(IntervalSignal.colorState(phase: .work, remaining: 10, phaseDuration: 60) == .warning)
        #expect(IntervalSignal.colorState(phase: .work, remaining: 10.001, phaseDuration: 60) == .work)
        #expect(IntervalSignal.colorState(phase: .work, remaining: 3.001, phaseDuration: 60) == .warning)
        #expect(IntervalSignal.colorState(phase: .work, remaining: 3, phaseDuration: 60) == .imminent)
    }

    @Test func shortWorkDoesNotStayWarningForEntirePhase() {
        #expect(IntervalSignal.colorState(phase: .work, remaining: 19, phaseDuration: 20) == .work)
        #expect(IntervalSignal.colorState(phase: .work, remaining: 5, phaseDuration: 20) == .warning)
        #expect(IntervalSignal.colorState(phase: .work, remaining: 3, phaseDuration: 20) == .imminent)
    }
}
