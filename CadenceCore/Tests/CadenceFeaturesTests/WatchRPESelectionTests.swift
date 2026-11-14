import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures

@Suite struct WatchRPESelectionTests {
    @Test func unsetShowsDash() {
        #expect(WatchRPESelection.rowText(mode: .rpe, value: nil) == "—")
    }

    @Test(arguments: [1, 10])
    func boundariesPresentAndStoreCanonicalRPE(_ n: Int) {
        var mode: WatchEffortMode = .rpe
        var value: Double?
        WatchRPESelection.apply(n, mode: &mode, value: &value)
        #expect(mode == .rpe)
        #expect(value == Double(n))
        #expect(WatchRPESelection.rowText(mode: mode, value: value) == "RPE \(n)")
        #expect(mode.rpeValue(from: value) == Double(n))
    }

    @Test func noneClearsEffort() {
        var mode: WatchEffortMode = .rpe
        var value: Double? = 8
        WatchRPESelection.apply(nil, mode: &mode, value: &value)
        #expect(mode == .rpe)
        #expect(value == nil)
        #expect(WatchRPESelection.rowText(mode: mode, value: value) == "—")
    }

    @Test func choosingNormalizesNonRPEMode() {
        var mode: WatchEffortMode = .rir
        var value: Double? = 2
        WatchRPESelection.apply(7, mode: &mode, value: &value)
        #expect(mode == .rpe)
        #expect(value == 7)
        #expect(WatchRPESelection.options == Array(1...10))
    }

    @Test func coachGuidanceOnlyWhenPlanLineExists() {
        #expect(WatchRPESelection.coachGuidance(from: nil) == nil)
        let rpe = WatchSetCardBuilder.planLine(
            planned: PlannedSetPrescription(targetReps: 5, targetWeightKg: 100, targetRPE: 8),
            prefillWeightKg: 100, lastTime: nil, unit: .kilograms, isWarmup: false)
        #expect(WatchRPESelection.coachGuidance(from: rpe) == rpe)
        #expect(rpe?.citationIDs == ["rpeAutoregulation"])
        let percent = WatchSetCardBuilder.planLine(
            planned: PlannedSetPrescription(targetReps: 5, targetWeightKg: 100, oneRepMaxPercent: 0.75),
            prefillWeightKg: 100, lastTime: nil, unit: .kilograms, isWarmup: false)
        #expect(WatchRPESelection.coachGuidance(from: percent)?.citationIDs == ["oneRMEstimation"])
        let plain = WatchSetCardBuilder.planLine(
            planned: PlannedSetPrescription(targetReps: 5, targetWeightKg: 102.5),
            prefillWeightKg: 102.5, lastTime: .init(weightKg: 100, reps: 5, rpe: 8),
            unit: .kilograms, isWarmup: false)
        #expect(WatchRPESelection.coachGuidance(from: plain)?.citationIDs == [])
        #expect(WatchRPESelection.coachGuidance(from: plain)?.text.contains("+2.5") == true)
    }
}
