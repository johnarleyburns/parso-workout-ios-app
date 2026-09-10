import Foundation
import XCTest
@testable import CadenceCore

final class UnifiedPlanPlanningTypesTests: XCTestCase {
    func testPlanningRequestRoundTripsFutureAuthoringInputs() throws {
        let request = PlanningRequest(
            goal: .hypertrophy,
            experience: .intermediate,
            daysPerWeek: 4,
            sessionLengthMinutes: 60,
            equipmentProfile: [.barbell, .dumbbell],
            constraints: [
                .avoidMovementPattern(.hinge),
                .maximumSessionMinutes(75)
            ],
            preferences: ["upper/lower", "short warm-up"],
            horizon: .mesocycle(weeks: 4),
            progression: .doubleProgression,
            periodization: .accumulationIntensificationDeload,
            wantsConditioning: true,
            referenceDate: Date(timeIntervalSince1970: 1_700_000_000))

        try request.validate()
        let data = try JSONEncoder().encode(request)
        XCTAssertEqual(try JSONDecoder().decode(PlanningRequest.self, from: data), request)
    }

    func testSchemeAndTemplateValidationCoverStructuredGeneration() throws {
        let scheme = SetScheme(
            id: SetSchemeID(raw: "double-progression"),
            displayName: "Double progression",
            kind: .doubleProgressionRange,
            params: SchemeParams(
                workingSets: 3,
                repTarget: .range(min: 8, max: 12),
                load: .absoluteWeight(value: 70, unit: .kg),
                effort: .rir(2),
                restSeconds: 120),
            goalAffinity: [.hypertrophy])

        try scheme.validate()

        let days = Weekday.mondayThroughSunday.map { PlanDay(weekday: $0) }
        let template = PlanTemplate(
            title: "Simple hypertrophy",
            goal: .hypertrophy,
            experienceLevel: .intermediate,
            daysPerWeek: 4,
            equipmentProfile: [.barbell, .dumbbell],
            weeks: [PlanWeek(index: 0, days: days)],
            description: "A reusable four-day starting template.")

        try template.validate()
    }

    func testReadinessRejectsEachInvalidRangeIndependently() {
        let invalidSignals = [
            ReadinessSignal(restingHR: 0),
            ReadinessSignal(sleepHours: 25),
            ReadinessSignal(selfReportedReadiness: 0),
            ReadinessSignal(sorenessByMuscle: [.chest: 4])
        ]

        for signal in invalidSignals {
            XCTAssertThrowsError(try signal.validate())
        }
    }

    func testRepeatRequestRequiresSourceAndNonnegativeTargets() throws {
        let request = PlanRepeatRequest(
            scope: .mesocycle,
            sourceWeekIndex: 0,
            targetWeekIndices: [1, 2],
            targetWeekdays: [.monday, .thursday])

        try request.validate()

        let invalid = PlanRepeatRequest(scope: .week, targetWeekIndices: [1])
        XCTAssertThrowsError(try invalid.validate()) { error in
            XCTAssertEqual(error as? UnifiedPlanValidationError, .invalidRepeatRequest)
        }
    }

    func testPlanValidatesPhaseMetadataAndPreservesAssistance() throws {
        let days = Weekday.mondayThroughSunday.map { PlanDay(weekday: $0) }
        let plan = Plan(
            title: "Assisted plan",
            weeks: [PlanWeek(index: 0, days: days)],
            phases: [PlanPhase(
                id: "base",
                title: "Base",
                durationCycles: 3,
                progression: .doubleProgression)],
            assistance: [.generated, .critiqued])

        try plan.validate()
        XCTAssertEqual(plan.assistance, [.generated, .critiqued])

        let invalid = Plan(
            title: "Invalid phase",
            weeks: [PlanWeek(index: 0, days: days)],
            phases: [PlanPhase(id: "", title: "", durationCycles: 0)])
        XCTAssertThrowsError(try invalid.validate()) { error in
            XCTAssertEqual(error as? UnifiedPlanValidationError, .invalidPlanMetadata)
        }
    }
}

private extension Weekday {
    static var mondayThroughSunday: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}
