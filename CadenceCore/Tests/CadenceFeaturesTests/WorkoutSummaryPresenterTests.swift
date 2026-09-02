import XCTest
import CadenceCore
import CadenceFeatures

final class WorkoutSummaryPresenterTests: XCTestCase {
    func testTopLabelLoaded() {
        XCTAssertEqual(WorkoutSummaryPresenter.topLabel(topKg: 100, bodyweight: false, unit: .kilograms), "100 kg")
    }

    func testTopLabelBodyweightOnly() {
        XCTAssertEqual(WorkoutSummaryPresenter.topLabel(topKg: 0, bodyweight: true, unit: .kilograms), "BW")
    }

    func testTopLabelBodyweightPlus() {
        XCTAssertEqual(WorkoutSummaryPresenter.topLabel(topKg: 10, bodyweight: true, unit: .kilograms), "BW + 10 kg")
    }

    func testHRSummaryEmpty() {
        XCTAssertEqual(WorkoutSummaryPresenter.hrChartAXSummary([]), "No heart rate samples")
    }

    func testHRSummaryIgnoresZeros() {
        XCTAssertEqual(WorkoutSummaryPresenter.hrChartAXSummary([0, 120, 140, 160]),
                       "Average 140, range 120 to 160 beats per minute, 3 samples")
    }

    // MARK: Read-only exercise detail (field test 2026-08-18 #1)

    private func setLine(_ kg: Double, _ reps: Int, bw: Bool = false) -> WorkoutSummaryData.SetLine {
        WorkoutSummaryData.SetLine(weightKg: kg, reps: reps, usesBodyweight: bw)
    }

    func testSetLineUsesPoundsWhenPreferred() {
        XCTAssertEqual(WorkoutSummaryPresenter.setLine(setLine(81.6466, 12), unit: .pounds), "180 lb x 12")
    }

    func testSetLineUsesKilogramsWhenPreferred() {
        XCTAssertEqual(WorkoutSummaryPresenter.setLine(setLine(100, 5), unit: .kilograms), "100 kg x 5")
    }

    func testSetLineRendersBodyweight() {
        XCTAssertEqual(WorkoutSummaryPresenter.setLine(setLine(0, 12, bw: true), unit: .pounds), "BW x 12")
    }

    func testSetLineRendersWeightedBodyweight() {
        XCTAssertEqual(WorkoutSummaryPresenter.setLine(setLine(10, 12, bw: true), unit: .kilograms),
                       "BW + 10 kg x 12")
    }

    func testPerformerSetsTextJoinsWithCommaSpace() {
        let me = WorkoutSummaryData.PerformerLine(
            name: "Me", isMe: true,
            sets: [setLine(81.6466, 12), setLine(86.1826, 10), setLine(90.7185, 8)])
        XCTAssertEqual(WorkoutSummaryPresenter.performerSetsText(me, unit: .pounds),
                       "180 lb x 12, 190 lb x 10, 200 lb x 8")
    }

    func testOrderedPerformersPutsMeFirst() {
        let line = exerciseLine(performers: [
            WorkoutSummaryData.PerformerLine(name: "Alex", isMe: false, sets: [setLine(60, 10)]),
            WorkoutSummaryData.PerformerLine(name: "Me", isMe: true, sets: [setLine(100, 5)])
        ])
        XCTAssertEqual(WorkoutSummaryPresenter.orderedPerformers(line).map(\.name), ["Me", "Alex"])
    }

    func testOrderedPerformersDropsEmptyPerformers() {
        let line = exerciseLine(performers: [
            WorkoutSummaryData.PerformerLine(name: "Me", isMe: true, sets: [setLine(100, 5)]),
            WorkoutSummaryData.PerformerLine(name: "Ghost", isMe: false, sets: [])
        ])
        XCTAssertEqual(WorkoutSummaryPresenter.orderedPerformers(line).map(\.name), ["Me"])
    }

    func testDoneSummaryKeepsSetsAttachedToTheirPerformer() {
        let line = exerciseLine(performers: [
            WorkoutSummaryData.PerformerLine(name: "Me", isMe: true,
                                             sets: [setLine(100, 5)]),
            WorkoutSummaryData.PerformerLine(name: "Alex", isMe: false,
                                             sets: [setLine(60, 12)])
        ])
        XCTAssertEqual(WorkoutSummaryPresenter.doneSummary(line, unit: .kilograms),
                       "Done: Me: 100 kg x 5; Alex: 60 kg x 12")
    }

    func testExpandedAccessibilityValueNamesEachPerformer() {
        let line = exerciseLine(performers: [
            WorkoutSummaryData.PerformerLine(name: "Me", isMe: true, sets: [setLine(100, 5)]),
            WorkoutSummaryData.PerformerLine(name: "Alex", isMe: false, sets: [setLine(60, 10)])
        ])
        XCTAssertEqual(WorkoutSummaryPresenter.expandedAccessibilityValue(line, unit: .kilograms),
                       "Me: 100 kg x 5. Alex: 60 kg x 10")
    }

    private func exerciseLine(performers: [WorkoutSummaryData.PerformerLine])
        -> WorkoutSummaryData.ExerciseLine {
        WorkoutSummaryData.ExerciseLine(name: "Bench Press", setCount: 1, topSetWeightKg: 100,
                                        reps: [5], performers: performers)
    }
}
