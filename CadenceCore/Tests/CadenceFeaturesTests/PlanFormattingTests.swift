import XCTest
import CadenceCore
@testable import CadenceFeatures

/// One formatter for planned sets, shared by the plan editor's compact row and
/// its per-performer lines (field test 2026-08-18 #4, decision D4).
final class PlanFormattingTests: XCTestCase {

    func testLoadedSetShowsWeightAndReps() {
        XCTAssertEqual(PlanFormatting.setLine(targetReps: 8, targetWeightKg: 100,
                                              isBodyweight: false, unit: .kilograms),
                       "100×8")
    }

    func testBodyweightMovementReadsBW() {
        XCTAssertEqual(PlanFormatting.setLine(targetReps: 12, targetWeightKg: nil,
                                              isBodyweight: true, unit: .kilograms),
                       "BW×12")
    }

    func testLoadedMovementWithNoResolvedWeightReadsEmDash() {
        XCTAssertEqual(PlanFormatting.setLine(targetReps: 10, targetWeightKg: nil,
                                              isBodyweight: false, unit: .kilograms),
                       "—×10")
        XCTAssertEqual(PlanFormatting.loadLabel(targetWeightKg: nil, isBodyweight: false,
                                                unit: .kilograms),
                       "—")
    }

    func testSetsLineJoinsEveryPlannedSet() {
        let sets = [EditableSet(targetReps: 8, targetWeight: 100),
                    EditableSet(targetReps: 6, targetWeight: 105)]
        XCTAssertEqual(PlanFormatting.setsLine(sets, isBodyweight: false, unit: .kilograms,
                                               separator: ", "),
                       "100×8, 105×6")
    }

    func testSoloExerciseRendersNoPerformerLines() {
        let solo = EditableExercise(name: "Bench Press",
                                    sets: [EditableSet(targetReps: 8, targetWeight: 100)],
                                    notes: "")
        XCTAssertTrue(PlanFormatting.orderedPerformerPlans(solo).isEmpty,
                      "A solo plan keeps its single unlabelled line")
    }

    func testPerformerLinesPutMeFirst() {
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

        XCTAssertEqual(PlanFormatting.orderedPerformerPlans(exercise).map(\.name), ["Me", "Alex"])
    }
}
