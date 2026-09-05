import Foundation
import XCTest
@testable import CadenceCore

final class UnifiedPlanModelTests: XCTestCase {
    func testUnifiedPlanRoundTripsAllItemFamiliesAndProvenance() throws {
        let set = PrescribedSet(
            setIndex: 0,
            kind: .working,
            repTarget: .range(min: 8, max: 10),
            load: .percent1RM(percent: 0.72, calculatedWeight: 72.5),
            targetRPE: 8,
            restSeconds: 120)
        let strength = StrengthItem(
            exerciseKey: ExerciseKey(raw: "barbell_bench_press"),
            order: 0,
            sets: [set])
        let cardio = CardioItem(
            order: 1,
            prescription: .steadyState(SteadyState(
                activity: .run,
                durationSeconds: 1_800,
                intensity: .heartRateZone(2))))
        let mobility = MobilityItem(
            order: 2,
            name: "Hip flexor stretch",
            rounds: 2,
            perRound: .duration(seconds: 30),
            eachSide: true)
        let instruction = InstructionItem(order: 3, text: "Keep the ribs stacked.")
        let session = Session(
            title: "Push + easy run",
            goal: .hypertrophy,
            items: [.strength(strength), .cardio(cardio),
                    .mobility(mobility), .instruction(instruction)])
        let monday = PlanDay(weekday: .monday, sessions: [session])
        let days = [monday] + Weekday.tuesdayThroughSunday.map { PlanDay(weekday: $0) }
        let plan = Plan(
            title: "Week one",
            provenance: .trainerAuthored(
                trainer: TrainerRef(displayName: "Maya", shareOwnerID: "owner-123")),
            horizon: .singleWeek,
            weeks: [PlanWeek(index: 0, days: days, intendedProgression: .doubleProgression)],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            authoredOnIdiom: .regular,
            rationale: EngineRationale(
                summary: "Balanced push and aerobic work.",
                knowledgeBaseVersion: "kb-test"))

        try plan.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Plan.self, from: encoder.encode(plan))

        XCTAssertEqual(decoded, plan)
        XCTAssertEqual(decoded.weeks[0].days[0].sessions[0].orderedItems.count, 4)
        XCTAssertEqual(decoded.weeks[0].days[0].sessions[0].orderedItems[0].id, strength.id)
    }

    func testPlanValidationRequiresCanonicalSevenDayWeeks() {
        let invalid = PlanWeek(index: 0, days: [PlanDay(weekday: .monday)])
        XCTAssertThrowsError(try invalid.validate()) { error in
            XCTAssertEqual(error as? UnifiedPlanValidationError, .weekMustHaveSevenDays)
        }
    }

    func testPlanValidationRejectsMoreThanTwoSessionsPerDay() {
        let sessions = (0..<3).map { Session(title: "Session \($0)") }
        let day = PlanDay(weekday: .monday, sessions: sessions)

        XCTAssertThrowsError(try day.validate()) { error in
            XCTAssertEqual(error as? UnifiedPlanValidationError,
                           .dayHasTooManySessions(.monday))
        }
    }

    func testSessionValidationRejectsDuplicateItemIDs() {
        let itemID = UUID()
        let first = InstructionItem(id: itemID, order: 0, text: "One")
        let second = InstructionItem(id: itemID, order: 1, text: "Two")
        let session = Session(title: "Duplicate", items: [
            .instruction(first), .instruction(second)
        ])

        XCTAssertThrowsError(try session.validate()) { error in
            XCTAssertEqual(error as? UnifiedPlanValidationError, .duplicateItemID)
        }
    }

    func testPlanHorizonMatchesWeekCount() {
        let days = Weekday.mondayThroughSunday.map { PlanDay(weekday: $0) }
        let plan = Plan(
            title: "Mesocycle",
            horizon: .mesocycle(weeks: 2),
            weeks: [PlanWeek(index: 0, days: days)])

        XCTAssertThrowsError(try plan.validate()) { error in
            XCTAssertEqual(error as? UnifiedPlanValidationError, .horizonMismatch)
        }
    }
}

private extension Weekday {
    static var tuesdayThroughSunday: [Weekday] {
        [.tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }

    static var mondayThroughSunday: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}
