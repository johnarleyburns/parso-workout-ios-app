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
}
