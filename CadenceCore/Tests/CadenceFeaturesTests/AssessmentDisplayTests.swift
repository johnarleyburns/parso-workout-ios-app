import Foundation
import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct AssessmentDisplayTests {
    @Test func valueReps() {
        #expect(AssessmentDisplay.value(32, kind: .pushupMax, unit: .kilograms) == "32 reps")
    }

    @Test func valueSeconds() {
        #expect(AssessmentDisplay.value(90, kind: .plankHold, unit: .kilograms) == "1:30")
    }

    @Test func valueWeight() {
        #expect(AssessmentDisplay.value(100, kind: .e1RM, unit: .kilograms) == "100 kg")
    }

    @Test func valueMlKgMin() {
        #expect(AssessmentDisplay.value(42.5, kind: .cooper12min, unit: .kilograms) == "42.5 mL/kg/min")
    }

    @Test func valueWatts() {
        #expect(AssessmentDisplay.value(850, kind: .wingate, unit: .kilograms) == "850 W")
    }

    @Test func seriesTitleLift() {
        let s = summary(kind: .e1RM, exercise: "Bench Press")
        #expect(AssessmentDisplay.seriesTitle(s) == "Bench Press 1RM")
    }

    @Test func seriesTitleRepMax() {
        let s = summary(kind: .repMax, exercise: "Deadlift")
        #expect(AssessmentDisplay.seriesTitle(s) == "Deadlift rep-max")
    }

    @Test func seriesTitleNonLiftUsesDisplayName() {
        let s = summary(kind: .pushupMax, exercise: nil)
        #expect(AssessmentDisplay.seriesTitle(s) == AssessmentKind.pushupMax.displayName)
    }

    private func summary(kind: AssessmentKind, exercise: String?) -> AssessmentSummary {
        AssessmentSummary(kind: kind, exerciseName: exercise, latest: 10, latestDate: Date(),
                          baseline: 8, baselineDate: Date(), best: 10, count: 2)
    }
}
