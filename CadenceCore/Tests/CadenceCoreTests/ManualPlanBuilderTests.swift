import XCTest
import SwiftData
@testable import CadenceCore

final class ManualPlanBuilderTests: XCTestCase {
    func testBlankPlanIsMondayFirstAndSelfAuthored() throws {
        let plan = ManualPlanBuilder.blankPlan(
            title: "Athlete week", now: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(plan.provenance, .selfAuthored)
        XCTAssertEqual(plan.status, .active)
        XCTAssertEqual(plan.weeks.count, 1)
        XCTAssertEqual(plan.weeks[0].days.map(\.weekday), ManualPlanBuilder.mondayFirst)
        try plan.validate()
    }

    func testAddAndReplaceSessionPreservesStableSessionAndSetIDs() throws {
        var plan = ManualPlanBuilder.blankPlan(now: Date(timeIntervalSince1970: 10))
        var session = ManualPlanBuilder.strengthSession(title: "Upper body")
        let item = ManualPlanBuilder.strengthItem(exerciseKey: "bench_press", setCount: 3, reps: 8)
        session.items = [.strength(item)]

        try ManualPlanBuilder.addSession(session, to: .monday, in: &plan,
                                         now: Date(timeIntervalSince1970: 20))
        let saved = try XCTUnwrap(plan.weeks[0].days[0].sessions.first)
        let setIDs = try XCTUnwrap(saved.items.first?.strengthSets.map(\.id))

        var edited = saved
        edited.title = "Upper body — revised"
        edited.items[0] = .strength(StrengthItem(
            id: item.id,
            exerciseKey: item.exerciseKey,
            order: item.order,
            sets: item.sets.map { set in
                PrescribedSet(id: set.id, setIndex: set.setIndex,
                              repTarget: .range(min: 8, max: 10), load: set.load)
            }))
        try ManualPlanBuilder.replaceSession(edited, in: &plan,
                                             now: Date(timeIntervalSince1970: 30))

        let replaced = try XCTUnwrap(plan.weeks[0].days[0].sessions.first)
        XCTAssertEqual(replaced.id, saved.id)
        XCTAssertEqual(replaced.title, "Upper body — revised")
        XCTAssertEqual(replaced.items.first?.strengthSets.map(\.id), setIDs)
        XCTAssertEqual(plan.updatedAt, Date(timeIntervalSince1970: 30))
    }

    func testDayCannotContainMoreThanTwoSessions() throws {
        var plan = ManualPlanBuilder.blankPlan()
        try ManualPlanBuilder.addSession(.init(title: "A"), to: .monday, in: &plan)
        try ManualPlanBuilder.addSession(.init(title: "B"), to: .monday, in: &plan)

        XCTAssertThrowsError(try ManualPlanBuilder.addSession(.init(title: "C"),
                                                               to: .monday, in: &plan)) { error in
            XCTAssertEqual(error as? UnifiedPlanValidationError, .dayHasTooManySessions(.monday))
        }
    }

    func testAuthoredPlanPersistsThroughEnvelopeAndNormalizedTree() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        var plan = ManualPlanBuilder.blankPlan(now: Date(timeIntervalSince1970: 10))
        var session = ManualPlanBuilder.strengthSession(title: "Monday strength")
        session.items = [.strength(ManualPlanBuilder.strengthItem(exerciseKey: "bench_press"))]
        try ManualPlanBuilder.addSession(session, to: .monday, in: &plan)

        _ = try UnifiedPlanStore.upsert(plan, originDevice: "iphone", in: context)
        _ = try NormalizedPlanStore.upsert(plan, originDevice: "iphone", in: context)

        XCTAssertEqual(try UnifiedPlanStore.fetch(id: plan.id, in: context), plan)
        XCTAssertEqual(try NormalizedPlanStore.fetch(id: plan.id, in: context), plan)
    }

    func testAllAuthoredItemFamiliesRoundTripWithStableIDs() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let strengthID = UUID()
        let cardioID = UUID()
        let mobilityID = UUID()
        let instructionID = UUID()
        let setID = UUID()

        var plan = ManualPlanBuilder.blankPlan(now: Date(timeIntervalSince1970: 10))
        var session = ManualPlanBuilder.strengthSession(title: "Mixed Monday")
        let intervalPrescription = CardioPrescription.intervals(Intervals(
            activity: .bike,
            rounds: 4,
            work: IntervalSegment(durationSeconds: 60,
                                  intensity: .heartRateZone(4)),
            recovery: IntervalSegment(durationSeconds: 120,
                                      intensity: .heartRateZone(2))))
        session.items = [
            .strength(StrengthItem(
                id: strengthID,
                exerciseKey: ExerciseKey(raw: "back_squat"),
                order: 0,
                sets: [PrescribedSet(id: setID, setIndex: 0, repTarget: .exact(5),
                                     load: .absoluteWeight(value: 100, unit: .kg))])),
            .cardio(CardioItem(
                id: cardioID,
                order: 1,
                prescription: intervalPrescription)),
            .mobility(MobilityItem(id: mobilityID, order: 2, name: "Couch stretch",
                                   rounds: 2, perRound: .duration(seconds: 30),
                                   eachSide: true)),
            .instruction(InstructionItem(id: instructionID, order: 3,
                                         text: "Leave two reps in reserve."))
        ]
        try ManualPlanBuilder.addSession(session, to: .monday, in: &plan,
                                         now: Date(timeIntervalSince1970: 20))

        _ = try UnifiedPlanStore.upsert(plan, originDevice: "iphone", in: context)
        _ = try NormalizedPlanStore.upsert(plan, originDevice: "iphone", in: context)

        let envelope = try XCTUnwrap(try UnifiedPlanStore.fetch(id: plan.id, in: context))
        let normalized = try XCTUnwrap(try NormalizedPlanStore.fetch(id: plan.id, in: context))
        let envelopeItems = try XCTUnwrap(envelope.weeks[0].days[0].sessions.first?.orderedItems)
        let normalizedItems = try XCTUnwrap(normalized.weeks[0].days[0].sessions.first?.orderedItems)

        XCTAssertEqual(envelopeItems.map(\.id), [strengthID, cardioID, mobilityID, instructionID])
        XCTAssertEqual(normalizedItems, envelopeItems)
        XCTAssertEqual(envelopeItems.first?.strengthSets.map(\.id), [setID])
        XCTAssertTrue(envelopeItems.contains { item in
            guard case let .cardio(value) = item else { return false }
            guard case let .intervals(intervals) = value.prescription else { return false }
            return intervals.rounds == 4
        })
    }
}

private extension WorkoutItem {
    var strengthSets: [PrescribedSet] {
        guard case let .strength(item) = self else { return [] }
        return item.sets
    }
}

private extension Session {
    var strengthSets: [PrescribedSet] {
        items.first?.strengthSets ?? []
    }
}
