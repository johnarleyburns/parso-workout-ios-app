import Foundation
import XCTest
@testable import CadenceCore

final class UnifiedPlanAuthoringTests: XCTestCase {
    func testTemplateInstantiationResolvesPercentOneRMAndUsesFreshPlanIdentity() throws {
        let prescribed = PrescribedSet(
            setIndex: 0,
            repTarget: .range(min: 6, max: 8),
            load: .percent1RM(percent: 0.75, calculatedWeight: nil),
            targetRIR: 2)
        let item = StrengthItem(
            exerciseKey: ExerciseKey(raw: "barbell_bench_press"),
            order: 0,
            sets: [prescribed])
        let session = Session(title: "Press", items: [.strength(item)])
        let days = Weekday.mondayThroughSunday.enumerated().map { index, weekday in
            PlanDay(weekday: weekday, sessions: index == 0 ? [session] : [])
        }
        let template = PlanTemplate(
            id: TemplateID(raw: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!),
            title: "Bench base",
            goal: .strength,
            daysPerWeek: 1,
            weeks: [PlanWeek(index: 0, days: days)],
            description: "A reusable press template.")
        let profile = ExercisePerformanceProfile(
            exerciseKey: ExerciseKey(raw: "barbell_bench_press"),
            estimates: [OneRMEstimatePoint(
                exerciseKey: ExerciseKey(raw: "barbell_bench_press"),
                valueKg: 100,
                formula: .blended,
                confidence: .high,
                source: .testedByTrainer)])
        let request = PlanningRequest(
            goal: .strength,
            experience: .intermediate,
            daysPerWeek: 1,
            performanceProfiles: [profile])

        let plan = try UnifiedPlanAuthoring.instantiate(
            template: template, from: request,
            now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertNotEqual(plan.id, PlanID(raw: template.id.raw))
        XCTAssertEqual(plan.provenance,
                       .templateAuthored(templateID: template.id, adaptedBy: .selfAthlete))
        guard case let .strength(materialized) = plan.weeks[0].days[0].sessions[0].items[0],
              case let .percent1RM(percent, calculatedWeight) = materialized.sets[0].load else {
            return XCTFail("Expected materialized percent-1RM prescription")
        }
        XCTAssertEqual(percent, 0.75)
        XCTAssertEqual(calculatedWeight, 75)
        XCTAssertNotEqual(materialized.id, item.id)
        XCTAssertNotEqual(materialized.sets[0].id, prescribed.id)
    }

    func testMesocycleCreatesPhasesProgressionAndDeloadWeek() throws {
        let item = StrengthItem(
            exerciseKey: ExerciseKey(raw: "back_squat"),
            order: 0,
            sets: [
                PrescribedSet(setIndex: 0, repTarget: .range(min: 8, max: 10),
                              load: .absoluteWeight(value: 100, unit: .kg)),
                PrescribedSet(setIndex: 1, repTarget: .range(min: 8, max: 10),
                              load: .absoluteWeight(value: 100, unit: .kg))
            ])
        let session = Session(title: "Lower", items: [.strength(item)])
        let days = Weekday.mondayThroughSunday.enumerated().map { index, weekday in
            PlanDay(weekday: weekday, sessions: index == 0 ? [session] : [])
        }
        let plan = Plan(title: "Base", weeks: [PlanWeek(index: 0, days: days)])

        let mesocycle = try UnifiedPlanAuthoring.mesocycle(
            from: plan,
            weeks: 4,
            periodization: .accumulationIntensificationDeload,
            progression: .doubleProgression)

        XCTAssertEqual(mesocycle.horizon, .mesocycle(weeks: 4))
        XCTAssertEqual(mesocycle.weeks.count, 4)
        XCTAssertEqual(mesocycle.phases?.map(\.id), ["accumulation", "intensification", "deload"])
        XCTAssertTrue(mesocycle.weeks.last?.isDeload == true)
        guard case let .strength(deloaded) = mesocycle.weeks.last?.days[0].sessions[0].orderedItems[0] else {
            return XCTFail("Expected deloaded strength item")
        }
        XCTAssertEqual(deloaded.sets.count, 1)
        XCTAssertEqual(mesocycle.weeks[1].days[0].sessions[0].orderedItems.count, 1)
        guard case let .strength(progressed) = mesocycle.weeks[1].days[0].sessions[0].items[0],
              case let .range(min, max) = progressed.sets[0].repTarget else {
            return XCTFail("Expected progressed range")
        }
        XCTAssertEqual(min, 9)
        XCTAssertEqual(max, 11)
        XCTAssertNotEqual(mesocycle.weeks[0].days[0].sessions[0].id,
                           mesocycle.weeks[1].days[0].sessions[0].id)
    }

    func testRepeatSessionCopiesToSelectedDayWithFreshExecutionIdentity() throws {
        let source = Session(title: "Full body")
        let days = Weekday.mondayThroughSunday.enumerated().map { index, weekday in
            PlanDay(weekday: weekday, sessions: index == 0 ? [source] : [])
        }
        var plan = Plan(title: "Week", weeks: [PlanWeek(index: 0, days: days)])

        try UnifiedPlanAuthoring.repeatSession(
            id: source.id, on: [.thursday], in: &plan)

        let thursday = try XCTUnwrap(plan.weeks[0].days.first(where: { $0.weekday == .thursday }))
        XCTAssertEqual(thursday.sessions.count, 1)
        XCTAssertNotEqual(thursday.sessions[0].id, source.id)
        XCTAssertEqual(plan.weeks[0].days[0].sessions.count, 1)
    }

    func testRepeatWeekExtendsExistingPlanAsMesocycle() throws {
        let days = Weekday.mondayThroughSunday.map { PlanDay(weekday: $0) }
        let original = PlanWeek(index: 0, days: days)
        var plan = Plan(title: "Week", weeks: [original])

        try UnifiedPlanAuthoring.repeatWeek(count: 2, in: &plan)

        XCTAssertEqual(plan.horizon, .mesocycle(weeks: 3))
        XCTAssertEqual(plan.weeks.map(\.index), [0, 1, 2])
        XCTAssertEqual(plan.weeks.count, 3)
        XCTAssertEqual(plan.weeks[0].id, original.id)
    }
}

private extension Weekday {
    static var mondayThroughSunday: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}
