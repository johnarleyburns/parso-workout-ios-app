import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

@MainActor
final class EditablePlanTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    func testFromSessionCopiesOwnerSets() throws {
        let ctx = try makeContext()
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        let s = WorkoutSession(title: "Push Day", date: Date()); ctx.insert(s)
        ctx.insert(SetEntry(weight: 100, reps: 5, order: 0, completedAt: s.date, session: s, exercise: bench))
        ctx.insert(SetEntry(weight: 100, reps: 4, order: 1, completedAt: s.date, session: s, exercise: bench))
        try ctx.save()

        let plan = EditablePlan.from(session: s)
        XCTAssertEqual(plan.title, "Push Day")
        XCTAssertEqual(plan.exercises.count, 1)
        XCTAssertEqual(plan.exercises.first?.sets.count, 2)
        XCTAssertEqual(plan.exercises.first?.sets.map(\.targetReps), [5, 4])
    }

    func testFromPlanSeedsSetsFromLadder() {
        let item = PlanItem(id: 1, movement: "Back Squat", reps: 5, targetSets: nil)
        let wp = WorkoutPlan(id: "preset", name: "5x5", source: .strengthPreset,
                             scheme: .strength, items: [item])
        let plan = EditablePlan.from(plan: wp, ladder: [5, 5, 5], unit: .kilograms)
        XCTAssertEqual(plan.title, "5x5")
        XCTAssertEqual(plan.exercises.count, 1)
        XCTAssertEqual(plan.exercises.first?.sets.count, 3)
        XCTAssertEqual(plan.exercises.first?.sets.map(\.targetReps), [5, 5, 5])
    }

    func testFromPlanWithoutLadderDefaultsToThreeSets() {
        let item = PlanItem(id: 1, movement: "Back Squat", reps: 8, targetSets: nil)
        let wp = WorkoutPlan(id: "p", name: "P", source: .strengthPreset, scheme: .strength, items: [item])
        let plan = EditablePlan.from(plan: wp, ladder: nil, unit: .kilograms)
        XCTAssertEqual(plan.exercises.first?.sets.count, 3)
        XCTAssertEqual(plan.exercises.first?.sets.map(\.targetReps), [8, 8, 8])
    }

    func testFromCoachSessionMapsExercises() {
        let ex = CoachSession.RecommendedExercise(name: "Bench Press", sets: 3, repsLow: 8, loadKg: 60, rir: 2)
        let session = CoachSession(id: "c1", kind: .strength, title: "Upper", exercises: [ex])
        let plan = EditablePlan.from(coach: session)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.title, "Upper")
        XCTAssertEqual(plan?.warmupMinutes, 5)
        XCTAssertEqual(plan?.exercises.first?.sets.count, 3)
        XCTAssertEqual(plan?.exercises.first?.sets.allSatisfy { $0.targetReps == 8 }, true)
        XCTAssertEqual(plan?.exercises.first?.notes, "Target ≤2 RIR")
    }

    func testFromCoachSessionNilWhenNoExercises() {
        let session = CoachSession(id: "c2", kind: .strength, title: "Empty", exercises: nil)
        XCTAssertNil(EditablePlan.from(coach: session))
    }

    func testNormalizedPartnerIDsDropsOwnerOnly() {
        let owner = UUID()
        XCTAssertEqual(EditablePlan.normalizedPartnerIDs([owner], ownerID: owner), [])
    }

    func testNormalizedPartnerIDsKeepsPartnersAndDedupes() {
        let owner = UUID(); let a = UUID(); let b = UUID()
        let result = EditablePlan.normalizedPartnerIDs([owner, a, a, b], ownerID: owner)
        XCTAssertEqual(result, [owner, a, b])
    }
}
