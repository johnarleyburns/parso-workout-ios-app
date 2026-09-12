import Foundation
import XCTest
@testable import CadenceCore

final class PlanningRequestPersistenceTests: XCTestCase {
    func testPlanRoundTripPreservesStructuredPlanningIntent() throws {
        let request = PlanningRequest(
            goal: .strength,
            experience: .advanced,
            daysPerWeek: 4,
            sessionLengthMinutes: 60,
            equipmentProfile: [.barbell],
            constraints: [.avoidMovementPattern(.hinge)],
            preferences: ["upper/lower"],
            horizon: .mesocycle(weeks: 4),
            progression: .doubleProgression,
            periodization: .accumulationIntensificationDeload,
            wantsConditioning: false,
            referenceDate: Date(timeIntervalSince1970: 1_700_000_000))
        let plan = Plan(
            title: "Strength block",
            horizon: .mesocycle(weeks: 1),
            weeks: [PlanWeek(index: 0, days: mondayFirst.map { PlanDay(weekday: $0) })],
            planningRequest: request)

        try plan.validate()
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(Plan.self, from: data)

        XCTAssertEqual(decoded.planningRequest, request)
    }

    private var mondayFirst: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}
