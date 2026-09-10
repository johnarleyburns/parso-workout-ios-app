import XCTest
@testable import CadenceFeatures
import CadenceCore

final class ManualPlanWatchBridgeTests: XCTestCase {
    func testTodayPlanCarriesAuthoredStrengthIdentityAndPrescription() throws {
        let planDate = date(year: 2026, month: 9, day: 7) // Monday
        let planDateValue = planDate
        var plan = ManualPlanBuilder.blankPlan(
            title: "Authored week", now: Date(timeIntervalSince1970: 10))
        let sessionID = UUID()
        let itemID = UUID()
        let setID = UUID()
        var session = Session(id: sessionID, title: "Monday strength")
        session.items = [.strength(StrengthItem(
            id: itemID,
            exerciseKey: ExerciseKey(raw: "back_squat"),
            order: 0,
            sets: [PrescribedSet(id: setID, setIndex: 0, repTarget: .exact(5),
                                 load: .absoluteWeight(value: 100, unit: .kg),
                                 targetRPE: 8, restSeconds: 150)]))]
        try ManualPlanBuilder.addSession(session, to: .monday, in: &plan,
                                         now: Date(timeIntervalSince1970: 20))

        let today = ManualPlanWatchBridge.todayPlan(
            from: plan,
            date: planDateValue,
            calendar: utcCalendar,
            exerciseNameByKey: ["back_squat": "Back Squat"])

        let watchSession = try XCTUnwrap(today.sessions.first)
        XCTAssertEqual(watchSession.id, sessionID.uuidString)
        XCTAssertEqual(watchSession.kind, .strength)
        XCTAssertEqual(watchSession.exerciseNames, ["Back Squat"])
        XCTAssertEqual(watchSession.repLadder, [5])
        XCTAssertEqual(watchSession.planPayload?.planSessionID, sessionID)
        XCTAssertEqual(watchSession.planPayload?.strength?.prescriptions.first?.sourceItemID, itemID)
        XCTAssertEqual(watchSession.planPayload?.strength?.prescriptions.first?.sets.first?.sourceSetID, setID)
        XCTAssertEqual(watchSession.planPayload?.strength?.prescriptions.first?.sets.first?.targetWeightKg, 100)
    }

    func testTodayPlanCarriesAuthoredCardioLegacyFieldsAndRichPayload() throws {
        let planDate = date(year: 2026, month: 9, day: 7) // Monday
        var plan = ManualPlanBuilder.blankPlan(now: Date(timeIntervalSince1970: 10))
        let sessionID = UUID()
        let cardioID = UUID()
        let cardio = CardioItem(
            id: cardioID,
            order: 0,
            prescription: .steadyState(SteadyState(
                activity: .run,
                durationSeconds: 1_800,
                distanceMeters: 5_000,
                intensity: .heartRateZone(2))))
        let session = Session(
            id: sessionID,
            title: "Easy run",
            items: [.cardio(cardio)])
        try ManualPlanBuilder.addSession(session, to: .monday, in: &plan)

        let today = ManualPlanWatchBridge.todayPlan(
            from: plan, date: planDate, calendar: utcCalendar)

        let watchSession = try XCTUnwrap(today.sessions.first)
        XCTAssertEqual(watchSession.id, sessionID.uuidString)
        XCTAssertEqual(watchSession.kind, .cardio)
        XCTAssertEqual(watchSession.cardioType, "run")
        XCTAssertEqual(watchSession.durationMinutes, 30)
        XCTAssertEqual(watchSession.zone, 2)
        XCTAssertEqual(watchSession.planPayload?.cardio.first?.id, cardioID)
        XCTAssertEqual(watchSession.planPayload?.cardio.first?.distanceMeters, 5_000)
    }

    func testInstructionOnlySessionDoesNotPretendToBeExecutableOnWatch() throws {
        let planDate = date(year: 2026, month: 9, day: 7) // Monday
        var plan = ManualPlanBuilder.blankPlan(now: Date(timeIntervalSince1970: 10))
        let session = Session(
            title: "Recovery notes",
            items: [.instruction(InstructionItem(order: 0, text: "Breathe slowly."))])
        try ManualPlanBuilder.addSession(session, to: .monday, in: &plan)

        let today = ManualPlanWatchBridge.todayPlan(
            from: plan, date: planDate, calendar: utcCalendar)

        XCTAssertTrue(today.sessions.isEmpty)
    }

    func testMixedStrengthAndCardioSessionIsNotMislabelledAsStrengthOnWatch() throws {
        let planDate = date(year: 2026, month: 9, day: 7) // Monday
        var plan = ManualPlanBuilder.blankPlan(now: Date(timeIntervalSince1970: 10))
        let session = Session(
            title: "Lift then run",
            items: [
                .strength(ManualPlanBuilder.strengthItem(exerciseKey: "back_squat")),
                .cardio(CardioItem(
                    order: 1,
                    prescription: .steadyState(SteadyState(
                        activity: .run, durationSeconds: 1_200))))
            ])
        try ManualPlanBuilder.addSession(session, to: .monday, in: &plan)

        let today = ManualPlanWatchBridge.todayPlan(
            from: plan,
            date: planDate,
            calendar: utcCalendar,
            exerciseNameByKey: ["back_squat": "Back Squat"])

        XCTAssertTrue(today.sessions.isEmpty)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
