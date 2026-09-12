import Foundation
import XCTest
@testable import CadenceCore

final class BoundedPlanningRequestParserTests: XCTestCase {
    func testParsesStructuredPlanningLanguageWithoutChoosingPrescriptions() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let result = BoundedPlanningRequestParser.parse(
            "Make me a 4 day hypertrophy plan with dumbbells for 45 minutes, 4 weeks, double progression, no squats",
            referenceDate: date)

        XCTAssertTrue(result.isActionable)
        XCTAssertEqual(result.unsupportedTerms, [])
        let request = try XCTUnwrap(result.request)
        XCTAssertEqual(request.goal, .hypertrophy)
        XCTAssertEqual(request.daysPerWeek, 4)
        XCTAssertEqual(request.sessionLengthMinutes, 45)
        XCTAssertEqual(request.equipmentProfile, [.dumbbell])
        XCTAssertEqual(request.horizon, .mesocycle(weeks: 4))
        XCTAssertEqual(request.progression, .doubleProgression)
        XCTAssertEqual(request.constraints, [.avoidMovementPattern(.squat)])
        XCTAssertEqual(request.referenceDate, date)
    }

    func testConditioningAndPassiveConstraintsRemainStructuredInputs() throws {
        let result = BoundedPlanningRequestParser.parse(
            "beginner conditioning with no lats and a deload")

        let request = try XCTUnwrap(result.request)
        XCTAssertEqual(request.goal, .endurance)
        XCTAssertTrue(request.wantsConditioning)
        XCTAssertEqual(request.experience, .beginner)
        XCTAssertEqual(request.periodization, .accumulationIntensificationDeload)
        XCTAssertEqual(request.constraints, [.avoidMuscleGroup(.lats)])
    }

    func testRetiredProductRequestsAreRejectedRatherThanGuessed() {
        let result = BoundedPlanningRequestParser.parse("make a trainer plan for my client")

        XCTAssertFalse(result.isActionable)
        XCTAssertNil(result.request)
        XCTAssertEqual(result.unsupportedTerms, ["client", "trainer"])
        XCTAssertNotNil(result.clarification)
    }

    func testUnknownTextRequiresClarification() {
        let result = BoundedPlanningRequestParser.parse("surprise me with something magical")

        XCTAssertFalse(result.isActionable)
        XCTAssertNil(result.request)
        XCTAssertTrue(result.recognizedTerms.isEmpty)
        XCTAssertNotNil(result.clarification)
    }
}
