import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures

@Suite struct WatchRPESelectionTests {
    @Test(arguments: [1, 10])
    func boundariesStoreCanonicalRPE(_ n: Int) {
        var mode: WatchEffortMode = .rpe
        var value: Double?
        WatchRPESelection.apply(n, mode: &mode, value: &value)
        #expect(mode == .rpe)
        #expect(value == Double(n))
        #expect(mode.rpeValue(from: value) == Double(n))
    }

    @Test func noneClearsEffort() {
        var mode: WatchEffortMode = .rpe
        var value: Double? = 8
        WatchRPESelection.apply(nil, mode: &mode, value: &value)
        #expect(mode == .rpe)
        #expect(value == nil)
    }

    @Test func choosingNormalizesNonRPEMode() {
        var mode: WatchEffortMode = .rir
        var value: Double? = 2
        WatchRPESelection.apply(7, mode: &mode, value: &value)
        #expect(mode == .rpe)
        #expect(value == 7)
        #expect(WatchRPESelection.options == Array(1...10))
    }
}
