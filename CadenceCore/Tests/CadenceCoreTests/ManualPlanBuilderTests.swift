#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

struct ManualPlanBuilderTests {
    @Test func blankPlanIsMondayFirstAndSelfAuthored() throws {
        let plan = ManualPlanBuilder.blankPlan(
            title: "Athlete week", now: Date(timeIntervalSince1970: 10))

        #expect(plan.provenance == .selfAuthored)
        #expect(plan.status == .active)
        #expect(plan.weeks.count == 1)
        #expect(plan.weeks[0].days.map(\.weekday) == ManualPlanBuilder.mondayFirst)
        try plan.validate()
    }

    @Test func addAndReplaceSessionPreservesStableSessionAndSetIDs() throws {
        var plan = ManualPlanBuilder.blankPlan(now: Date(timeIntervalSince1970: 10))
        var session = ManualPlanBuilder.strengthSession(title: "Upper body")
        let item = ManualPlanBuilder.strengthItem(exerciseKey: "bench_press", setCount: 3, reps: 8)
        session.items = [.strength(item)]

        try ManualPlanBuilder.addSession(session, to: .monday, in: &plan,
                                         now: Date(timeIntervalSince1970: 20))
        let saved = try #require(plan.weeks[0].days[0].sessions.first)
        let setIDs = try #require(saved.items.first?.strengthSets.map(\.id))

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

        let replaced = try #require(plan.weeks[0].days[0].sessions.first)
        #expect(replaced.id == saved.id)
        #expect(replaced.title == "Upper body — revised")
        #expect(replaced.items.first?.strengthSets.map(\.id) == setIDs)
        #expect(plan.updatedAt == Date(timeIntervalSince1970: 30))
    }

    @Test func dayCannotContainMoreThanTwoSessions() throws {
        var plan = ManualPlanBuilder.blankPlan()
        try ManualPlanBuilder.addSession(.init(title: "A"), to: .monday, in: &plan)
        try ManualPlanBuilder.addSession(.init(title: "B"), to: .monday, in: &plan)

        #expect(throws: UnifiedPlanValidationError.dayHasTooManySessions(.monday)) {
            try ManualPlanBuilder.addSession(.init(title: "C"), to: .monday, in: &plan)
        }
    }

    @Test func authoredPlanPersistsThroughEnvelopeAndNormalizedTree() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        var plan = ManualPlanBuilder.blankPlan(now: Date(timeIntervalSince1970: 10))
        var session = ManualPlanBuilder.strengthSession(title: "Monday strength")
        session.items = [.strength(ManualPlanBuilder.strengthItem(exerciseKey: "bench_press"))]
        try ManualPlanBuilder.addSession(session, to: .monday, in: &plan)

        _ = try UnifiedPlanStore.upsert(plan, originDevice: "iphone", in: context)
        _ = try NormalizedPlanStore.upsert(plan, originDevice: "iphone", in: context)

        #expect(try UnifiedPlanStore.fetch(id: plan.id, in: context) == plan)
        #expect(try NormalizedPlanStore.fetch(id: plan.id, in: context) == plan)
    }

    @Test func allAuthoredItemFamiliesRoundTripWithStableIDs() throws {
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

        let envelope = try #require(try UnifiedPlanStore.fetch(id: plan.id, in: context))
        let normalized = try #require(try NormalizedPlanStore.fetch(id: plan.id, in: context))
        let envelopeItems = try #require(envelope.weeks[0].days[0].sessions.first?.orderedItems)
        let normalizedItems = try #require(normalized.weeks[0].days[0].sessions.first?.orderedItems)

        #expect(envelopeItems.map(\.id) == [strengthID, cardioID, mobilityID, instructionID])
        #expect(normalizedItems == envelopeItems)
        #expect(envelopeItems.first?.strengthSets.map(\.id) == [setID])
        #expect(envelopeItems.contains { item in
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
#endif
