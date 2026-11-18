import Foundation
import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

/// One formatter for planned sets, shared by the plan editor's compact row and
/// its per-performer lines (field test 2026-08-18 #4, decision D4).
struct PlanFormattingTests {

    @Test func loadedSetShowsWeightAndReps() {
        #expect(PlanFormatting.setLine(targetReps: 8, targetWeightKg: 100,
                                              isBodyweight: false, unit: .kilograms)
                       == "100×8")
    }

    @Test func bodyweightMovementReadsBW() {
        #expect(PlanFormatting.setLine(targetReps: 12, targetWeightKg: nil,
                                              isBodyweight: true, unit: .kilograms)
                       == "BW×12")
    }

    @Test func loadedMovementWithNoResolvedWeightReadsEmDash() {
        #expect(PlanFormatting.setLine(targetReps: 10, targetWeightKg: nil,
                                              isBodyweight: false, unit: .kilograms)
                       == "—×10")
        #expect(PlanFormatting.loadLabel(targetWeightKg: nil, isBodyweight: false,
                                                unit: .kilograms)
                       == "—")
    }

    @Test func setsLineJoinsEveryPlannedSet() {
        let sets = [EditableSet(targetReps: 8, targetWeight: 100),
                    EditableSet(targetReps: 6, targetWeight: 105)]
        #expect(PlanFormatting.setsLine(sets, isBodyweight: false, unit: .kilograms,
                                               separator: ", ")
                       == "100×8, 105×6")
    }

    @Test func soloExerciseRendersNoPerformerLines() {
        let solo = EditableExercise(name: "Bench Press",
                                    sets: [EditableSet(targetReps: 8, targetWeight: 100)],
                                    notes: "")
        #expect(PlanFormatting.orderedPerformerPlans(solo).isEmpty,
                      "A solo plan keeps its single unlabelled line")
    }

    @Test func performerLinesPutMeFirst() {
        let alex = UUID()
        let exercise = EditableExercise(
            name: "Bench Press",
            sets: [EditableSet(targetReps: 8, targetWeight: 100)],
            notes: "",
            performerPlans: [
                EditablePerformerPlan(performerID: alex, name: "Alex",
                                      sets: [EditableSet(targetReps: 12, targetWeight: 60)]),
                EditablePerformerPlan(performerID: nil, name: "Me",
                                      sets: [EditableSet(targetReps: 8, targetWeight: 100)])
            ])

        #expect(PlanFormatting.orderedPerformerPlans(exercise).map(\.name) == ["Me", "Alex"])
    }
}
