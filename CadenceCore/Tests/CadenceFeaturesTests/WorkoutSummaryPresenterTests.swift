import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct WorkoutSummaryPresenterTests {
    @Test func topLabelLoaded() {
        #expect(WorkoutSummaryPresenter.topLabel(topKg: 100, bodyweight: false, unit: .kilograms) == "100 kg")
    }

    @Test func topLabelBodyweightOnly() {
        #expect(WorkoutSummaryPresenter.topLabel(topKg: 0, bodyweight: true, unit: .kilograms) == "BW")
    }

    @Test func topLabelBodyweightPlus() {
        #expect(WorkoutSummaryPresenter.topLabel(topKg: 10, bodyweight: true, unit: .kilograms) == "BW + 10 kg")
    }

    @Test func hRSummaryEmpty() {
        #expect(WorkoutSummaryPresenter.hrChartAXSummary([]) == "No heart rate samples")
    }

    @Test func hRSummaryIgnoresZeros() {
        #expect(WorkoutSummaryPresenter.hrChartAXSummary([0, 120, 140, 160]) ==
                       "Average 140, range 120 to 160 beats per minute, 3 samples")
    }

    // MARK: Read-only exercise detail (field test 2026-08-18 #1)

    private func setLine(_ kg: Double, _ reps: Int, bw: Bool = false) -> WorkoutSummaryData.SetLine {
        WorkoutSummaryData.SetLine(weightKg: kg, reps: reps, usesBodyweight: bw)
    }

    @Test func setLineUsesPoundsWhenPreferred() {
        #expect(WorkoutSummaryPresenter.setLine(setLine(81.6466, 12), unit: .pounds) == "180 lb x 12")
    }

    @Test func setLineUsesKilogramsWhenPreferred() {
        #expect(WorkoutSummaryPresenter.setLine(setLine(100, 5), unit: .kilograms) == "100 kg x 5")
    }

    @Test func setLineRendersBodyweight() {
        #expect(WorkoutSummaryPresenter.setLine(setLine(0, 12, bw: true), unit: .pounds) == "BW x 12")
    }

    @Test func zeroLoadNonBodyweightStaysZeroNotBW() {
        #expect(WorkoutSummaryPresenter.setLine(setLine(0, 20), unit: .pounds) == "0 lb x 20")
        #expect(WorkoutSummaryPresenter.setLine(setLine(0, 20, bw: true), unit: .pounds) == "BW x 20")
    }

    @Test func setLineRendersWeightedBodyweight() {
        #expect(WorkoutSummaryPresenter.setLine(setLine(10, 12, bw: true), unit: .kilograms) ==
                       "BW + 10 kg x 12")
    }

    @Test func performerSetsTextJoinsWithCommaSpace() {
        let me = WorkoutSummaryData.PerformerLine(
            name: "Me", isMe: true,
            sets: [setLine(81.6466, 12), setLine(86.1826, 10), setLine(90.7185, 8)])
        #expect(WorkoutSummaryPresenter.performerSetsText(me, unit: .pounds) ==
                       "180 lb x 12, 190 lb x 10, 200 lb x 8")
    }

    @Test func orderedPerformersPutsMeFirst() {
        let line = exerciseLine(performers: [
            WorkoutSummaryData.PerformerLine(name: "Alex", isMe: false, sets: [setLine(60, 10)]),
            WorkoutSummaryData.PerformerLine(name: "Me", isMe: true, sets: [setLine(100, 5)])
        ])
        #expect(WorkoutSummaryPresenter.orderedPerformers(line).map(\.name) == ["Me", "Alex"])
    }

    @Test func orderedPerformersDropsEmptyPerformers() {
        let line = exerciseLine(performers: [
            WorkoutSummaryData.PerformerLine(name: "Me", isMe: true, sets: [setLine(100, 5)]),
            WorkoutSummaryData.PerformerLine(name: "Ghost", isMe: false, sets: [])
        ])
        #expect(WorkoutSummaryPresenter.orderedPerformers(line).map(\.name) == ["Me"])
    }

    @Test func doneSummaryKeepsSetsAttachedToTheirPerformer() {
        let line = exerciseLine(performers: [
            WorkoutSummaryData.PerformerLine(name: "Me", isMe: true,
                                             sets: [setLine(100, 5)]),
            WorkoutSummaryData.PerformerLine(name: "Alex", isMe: false,
                                             sets: [setLine(60, 12)])
        ])
        #expect(WorkoutSummaryPresenter.doneSummary(line, unit: .kilograms) ==
                       "Done: Me: 100 kg x 5; Alex: 60 kg x 12")
    }

    @Test func expandedAccessibilityValueNamesEachPerformer() {
        let line = exerciseLine(performers: [
            WorkoutSummaryData.PerformerLine(name: "Me", isMe: true, sets: [setLine(100, 5)]),
            WorkoutSummaryData.PerformerLine(name: "Alex", isMe: false, sets: [setLine(60, 10)])
        ])
        #expect(WorkoutSummaryPresenter.expandedAccessibilityValue(line, unit: .kilograms) ==
                       "Me: 100 kg x 5. Alex: 60 kg x 10")
    }

    private func exerciseLine(performers: [WorkoutSummaryData.PerformerLine])
        -> WorkoutSummaryData.ExerciseLine {
        WorkoutSummaryData.ExerciseLine(name: "Bench Press", setCount: 1, topSetWeightKg: 100,
                                        reps: [5], performers: performers)
    }
}
