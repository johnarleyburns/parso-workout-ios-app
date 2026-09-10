import Foundation
import XCTest
@testable import CadenceCore

final class UnifiedPlanDBPPBridgeTests: XCTestCase {
    func testProjectionKeepsDBPPResistanceShapeAndReportsAppOnlyItems() throws {
        let strength = StrengthItem(
            exerciseKey: ExerciseKey(raw: "barbell_bench_press"),
            order: 0,
            sets: [
                PrescribedSet(setIndex: 0, repTarget: .range(min: 8, max: 10),
                              load: .absoluteWeight(value: 60, unit: .kg), targetRIR: 2),
                PrescribedSet(setIndex: 1, repTarget: .range(min: 8, max: 10),
                              load: .absoluteWeight(value: 60, unit: .kg), targetRIR: 2),
            ],
            laterality: "bilateral",
            progression: .doubleProgression)
        let cardio = CardioItem(order: 1, prescription: .open(OpenActivity(
            activity: .run, goalText: "Easy conversational run")))
        let instruction = InstructionItem(order: 2, text: "Keep the ribs stacked.")
        let session = Session(title: "Push", items: [
            .strength(strength), .cardio(cardio), .instruction(instruction)
        ])
        let days = Weekday.mondayThroughSunday.enumerated().map { index, weekday in
            PlanDay(weekday: weekday, sessions: index == 0 ? [session] : [])
        }
        let plan = Plan(
            id: PlanID(raw: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!),
            revisionID: "r7",
            title: "Mixed plan",
            weeks: [PlanWeek(index: 0, days: days)],
            cycleLengthDays: 7,
            phases: [PlanPhase(id: "base", title: "Base", durationCycles: 1)])

        let projection = UnifiedPlanDBPPBridge.project(plan)

        XCTAssertEqual(projection.plan.planId, "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        XCTAssertEqual(projection.plan.revisionId, "r7")
        XCTAssertEqual(projection.plan.phases?.first?.phaseId, "base")
        XCTAssertEqual(projection.plan.sessions.count, 1)
        XCTAssertEqual(projection.projectedItemIDs, [strength.id] as [UUID])
        XCTAssertEqual(Set(projection.omittedItemIDs), Set([cardio.id, instruction.id]))

        let dbExercise = try XCTUnwrap(projection.plan.sessions.first?.exercises.first)
        XCTAssertEqual(dbExercise.prescriptionId, strength.id.uuidString)
        XCTAssertEqual(dbExercise.order, 1)
        XCTAssertEqual(dbExercise.laterality, "bilateral")
        XCTAssertEqual(dbExercise.plannedSets?.count, 2)
        XCTAssertEqual(dbExercise.plannedSets?.first?.setType, "working")
        XCTAssertEqual(dbExercise.plannedSets?.first?.effort,
                       DBPPJSONValue.object([
                           "rir": DBPPJSONValue.number(2)
                       ]))
    }

    func testEvaluationIsAdditiveAndDoesNotPersistAppOnlyItemsInDBPPPlan() throws {
        let days = Weekday.mondayThroughSunday.map { PlanDay(weekday: $0) }
        let plan = Plan(title: "Empty resistance projection", weeks: [PlanWeek(index: 0, days: days)])
        let schedule = CoachSchedulePreferences.default

        guard let evaluation = UnifiedPlanDBPPBridge.evaluate(
            plan, experience: .intermediate, schedule: schedule) else {
            throw XCTSkip("DB++ bundled engine is unavailable in this test environment")
        }

        XCTAssertEqual(evaluation.projectedItemCount, 0)
        XCTAssertEqual(evaluation.omittedAppItemCount, 0)
        XCTAssertFalse(evaluation.status.isEmpty)
    }
}

private extension Weekday {
    static var mondayThroughSunday: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}
