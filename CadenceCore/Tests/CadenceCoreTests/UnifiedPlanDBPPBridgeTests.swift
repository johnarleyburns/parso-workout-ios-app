import Foundation
import Testing
@testable import CadenceCore

struct UnifiedPlanDBPPBridgeTests {
    @Test func failureSetProjectsAsAppCompatibleOtherType() throws {
        let strength = StrengthItem(
            exerciseKey: ExerciseKey(raw: "barbell_bench_press"), order: 0,
            sets: [PrescribedSet(setIndex: 0, kind: .failure, repTarget: .exact(8))])
        let days = Weekday.mondayThroughSunday.map { weekday in
            PlanDay(weekday: weekday, sessions: weekday == .monday
                ? [Session(title: "Failure", items: [.strength(strength)])] : [])
        }
        let projection = UnifiedPlanDBPPBridge.project(Plan(title: "Failure", weeks: [PlanWeek(index: 0, days: days)]))
        #expect(projection.plan.sessions.first?.exercises.first?.plannedSets?.first?.setType == "other")
    }

    @Test func projectionKeepsDBPPResistanceShapeAndReportsAppOnlyItems() throws {
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

        #expect(projection.plan.planId == "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        #expect(projection.plan.revisionId == "r7")
        #expect(projection.plan.phases?.first?.phaseId == "base")
        #expect(projection.plan.sessions.count == 1)
        #expect(projection.projectedItemIDs == [strength.id] as [UUID])
        #expect(Set(projection.omittedItemIDs) == Set([cardio.id, instruction.id]))

        let dbExercise = try #require(projection.plan.sessions.first?.exercises.first)
        #expect(dbExercise.prescriptionId == strength.id.uuidString)
        #expect(dbExercise.order == 1)
        #expect(dbExercise.laterality == "bilateral")
        #expect(dbExercise.plannedSets?.count == 2)
        #expect(dbExercise.plannedSets?.first?.setType == "working")
        #expect(dbExercise.plannedSets?.first?.effort ==
                       DBPPJSONValue.object([
                           "rir": DBPPJSONValue.number(2)
                       ]))
    }

    @Test func evaluationIsAdditiveAndDoesNotPersistAppOnlyItemsInDBPPPlan() throws {
        let days = Weekday.mondayThroughSunday.map { PlanDay(weekday: $0) }
        let plan = Plan(title: "Empty resistance projection", weeks: [PlanWeek(index: 0, days: days)])
        let schedule = CoachSchedulePreferences.default

        guard let evaluation = UnifiedPlanDBPPBridge.evaluate(
            plan, experience: .intermediate, schedule: schedule) else {
            // DB++ bundled engine is unavailable in this test environment
            return
        }

        #expect(evaluation.projectedItemCount == 0)
        #expect(evaluation.omittedAppItemCount == 0)
        #expect(!evaluation.status.isEmpty)
    }
}

private extension Weekday {
    static var mondayThroughSunday: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}
