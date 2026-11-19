import Foundation
import Testing
@testable import CadenceCore

struct UnifiedPlanPlanningTypesTests {
    @Test func planningRequestRoundTripsFutureAuthoringInputs() throws {
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
        #expect(try JSONDecoder().decode(PlanningRequest.self, from: data) == request)
    }

    @Test func schemeValidationCoversStructuredGeneration() throws {
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
    }

    @Test func readinessRejectsEachInvalidRangeIndependently() {
        let invalidSignals = [
            ReadinessSignal(restingHR: 0),
            ReadinessSignal(sleepHours: 25),
            ReadinessSignal(selfReportedReadiness: 0),
            ReadinessSignal(sorenessByMuscle: [.chest: 4])
        ]

        for signal in invalidSignals {
            #expect(throws: (any Error).self) {
                try signal.validate()
            }
        }
    }

    @Test func repeatRequestRequiresSourceAndNonnegativeTargets() throws {
        let request = PlanRepeatRequest(
            scope: .mesocycle,
            sourceWeekIndex: 0,
            targetWeekIndices: [1, 2],
            targetWeekdays: [.monday, .thursday])

        try request.validate()

        let invalid = PlanRepeatRequest(scope: .week, targetWeekIndices: [1])
        #expect(throws: UnifiedPlanValidationError.invalidRepeatRequest) {
            try invalid.validate()
        }
    }

    @Test func planValidatesPhaseMetadataAndPreservesAssistance() throws {
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
        #expect(plan.assistance == [.generated, .critiqued])

        let invalid = Plan(
            title: "Invalid phase",
            weeks: [PlanWeek(index: 0, days: days)],
            phases: [PlanPhase(id: "", title: "", durationCycles: 0)])
        #expect(throws: UnifiedPlanValidationError.invalidPlanMetadata) {
            try invalid.validate()
        }
    }
}

private extension Weekday {
    static var mondayThroughSunday: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}
