import Foundation
import Testing
@testable import CadenceCore

struct BoundedPlanningRequestParserTests {
    @Test func parsesStructuredPlanningLanguageWithoutChoosingPrescriptions() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let result = BoundedPlanningRequestParser.parse(
            "Make me a 4 day hypertrophy plan with dumbbells for 45 minutes, 4 weeks, double progression, no squats",
            referenceDate: date)

        #expect(result.isActionable)
        #expect(result.unsupportedTerms == [])
        let request = try #require(result.request)
        #expect(request.goal == .hypertrophy)
        #expect(request.daysPerWeek == 4)
        #expect(request.sessionLengthMinutes == 45)
        #expect(request.equipmentProfile == [.dumbbell])
        #expect(request.horizon == .mesocycle(weeks: 4))
        #expect(request.progression == .doubleProgression)
        #expect(request.constraints == [.avoidMovementPattern(.squat)])
        #expect(request.referenceDate == date)
    }

    @Test func conditioningAndPassiveConstraintsRemainStructuredInputs() throws {
        let result = BoundedPlanningRequestParser.parse(
            "beginner conditioning with no lats and a deload")

        let request = try #require(result.request)
        #expect(request.goal == .endurance)
        #expect(request.wantsConditioning)
        #expect(request.experience == .beginner)
        #expect(request.periodization == .accumulationIntensificationDeload)
        #expect(request.constraints == [.avoidMuscleGroup(.lats)])
    }

    @Test func retiredProductRequestsAreRejectedRatherThanGuessed() {
        let result = BoundedPlanningRequestParser.parse("make a trainer plan for my client")

        #expect(!result.isActionable)
        #expect(result.request == nil)
        #expect(result.unsupportedTerms == ["client", "trainer"])
        #expect(result.clarification != nil)
    }

    @Test func unknownTextRequiresClarification() {
        let result = BoundedPlanningRequestParser.parse("surprise me with something magical")

        #expect(!result.isActionable)
        #expect(result.request == nil)
        #expect(result.recognizedTerms.isEmpty)
        #expect(result.clarification != nil)
    }
}
