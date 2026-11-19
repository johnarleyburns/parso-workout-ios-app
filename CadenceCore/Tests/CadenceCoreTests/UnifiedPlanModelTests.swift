import Foundation
import Testing
@testable import CadenceCore

struct UnifiedPlanModelTests {
    @Test func failureAndSupersetSemanticsRoundTripThroughTheUnifiedPlan() throws {
        let failure = PrescribedSet(setIndex: 0, kind: .failure, repTarget: .exact(8))
        let item = StrengthItem(exerciseKey: ExerciseKey(raw: "bench_press"), order: 0,
                                sets: [failure], supersetGroup: SupersetGroupID(raw: "A"))
        let session = Session(title: "Superset", items: [.strength(item)])
        let snapshot = PlanSessionSnapshot(session: session)

        #expect(snapshot.strengthItems.first?.supersetGroup == "A")
        #expect(snapshot.strengthItems.first?.sets.first?.kind == .failure)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PlanSessionSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test func legacyPlannedSetDefaultsToWorkingKind() throws {
        let legacy = Data(#"{"targetReps":8,"targetWeightKg":60}"#.utf8)
        let decoded = try JSONDecoder().decode(PlannedSetPrescription.self, from: legacy)
        #expect(decoded.kind == .working)
    }

    @Test func unifiedPlanRoundTripsAllItemFamiliesAndProvenance() throws {
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

        #expect(decoded == plan)
        #expect(decoded.weeks[0].days[0].sessions[0].orderedItems.count == 4)
        #expect(decoded.weeks[0].days[0].sessions[0].orderedItems[0].id == strength.id)
    }

    @Test func planValidationRequiresCanonicalSevenDayWeeks() {
        let invalid = PlanWeek(index: 0, days: [PlanDay(weekday: .monday)])
        #expect(throws: UnifiedPlanValidationError.weekMustHaveSevenDays) {
            try invalid.validate()
        }
    }

    @Test func planValidationRejectsMoreThanTwoSessionsPerDay() {
        let sessions = (0..<3).map { Session(title: "Session \($0)") }
        let day = PlanDay(weekday: .monday, sessions: sessions)

        #expect(throws: UnifiedPlanValidationError.dayHasTooManySessions(.monday)) {
            try day.validate()
        }
    }

    @Test func sessionValidationRejectsDuplicateItemIDs() {
        let itemID = UUID()
        let first = InstructionItem(id: itemID, order: 0, text: "One")
        let second = InstructionItem(id: itemID, order: 1, text: "Two")
        let session = Session(title: "Duplicate", items: [
            .instruction(first), .instruction(second)
        ])

        #expect(throws: UnifiedPlanValidationError.duplicateItemID) {
            try session.validate()
        }
    }

    @Test func planHorizonMatchesWeekCount() {
        let days = Weekday.mondayThroughSunday.map { PlanDay(weekday: $0) }
        let plan = Plan(
            title: "Mesocycle",
            horizon: .mesocycle(weeks: 2),
            weeks: [PlanWeek(index: 0, days: days)])

        #expect(throws: UnifiedPlanValidationError.horizonMismatch) {
            try plan.validate()
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
