import XCTest
import CadenceCore
import CadenceFeatures

final class AssessmentDisplayTests: XCTestCase {
    func testValueReps() {
        XCTAssertEqual(AssessmentDisplay.value(32, kind: .pushupMax, unit: .kilograms), "32 reps")
    }

    func testValueSeconds() {
        XCTAssertEqual(AssessmentDisplay.value(90, kind: .plankHold, unit: .kilograms), "1:30")
    }

    func testValueWeight() {
        XCTAssertEqual(AssessmentDisplay.value(100, kind: .e1RM, unit: .kilograms), "100 kg")
    }

    func testValueMlKgMin() {
        XCTAssertEqual(AssessmentDisplay.value(42.5, kind: .cooper12min, unit: .kilograms), "42.5 mL/kg/min")
    }

    func testValueWatts() {
        XCTAssertEqual(AssessmentDisplay.value(850, kind: .wingate, unit: .kilograms), "850 W")
    }

    func testSeriesTitleLift() {
        let s = summary(kind: .e1RM, exercise: "Bench Press")
        XCTAssertEqual(AssessmentDisplay.seriesTitle(s), "Bench Press 1RM")
    }

    func testSeriesTitleRepMax() {
        let s = summary(kind: .repMax, exercise: "Deadlift")
        XCTAssertEqual(AssessmentDisplay.seriesTitle(s), "Deadlift rep-max")
    }

    func testSeriesTitleNonLiftUsesDisplayName() {
        let s = summary(kind: .pushupMax, exercise: nil)
        XCTAssertEqual(AssessmentDisplay.seriesTitle(s), AssessmentKind.pushupMax.displayName)
    }

    private func summary(kind: AssessmentKind, exercise: String?) -> AssessmentSummary {
        AssessmentSummary(kind: kind, exerciseName: exercise, latest: 10, latestDate: Date(),
                          baseline: 8, baselineDate: Date(), best: 10, count: 2)
    }
}
