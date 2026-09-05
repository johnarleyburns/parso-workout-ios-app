import XCTest
@testable import CadenceCore

final class WeeklyPlanUnifiedBridgeTests: XCTestCase {
    func testBridgeProducesValidatedSevenDayPlanWithRichStrengthAndCardio() throws {
        let calendar = Calendar.current
        let monday = WeeklyStats.weekStart(now: Date(timeIntervalSince1970: 1_000_000))
        let strength = PlannedSession(
            id: "coach-strength",
            kind: .strength,
            label: "Strength",
            isHard: true,
            isRest: false,
            exercises: [CoachSession.RecommendedExercise(
                name: "Bench Press", sets: 3, repsLow: 8, repsHigh: 10,
                loadKg: 60, rir: 2, repLadder: [10, 9, 8]),
            CoachSession.RecommendedExercise(
                name: "Bench Press", sets: 1, repsLow: 5,
                loadKg: 70, rir: 1, repLadder: [5])])
        let cardio = PlannedSession(
            id: "coach-run", kind: .moderateAerobic, label: "Steady run",
            isHard: true, isRest: false, cardioDurationMinutes: 25, cardioZone: 3)
        let outlines = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: monday)!
            return WeeklyPlan.DayOutline(
                date: date, label: offset == 0 ? "Strength + run" : "Rest",
                sessions: offset == 0 ? [strength, cardio] : [])
        }
        let weekly = WeeklyPlan(days: outlines, generatedAt: monday)

        let first = WeeklyPlanUnifiedBridge.plan(from: weekly)
        let second = WeeklyPlanUnifiedBridge.plan(from: weekly)
        try first.validate()

        XCTAssertEqual(first, second, "IDs must not change when the same coach plan is rebuilt")
        XCTAssertEqual(first.weeks.first?.days.count, 7)
        XCTAssertEqual(first.weeks.first?.days.first?.sessions.count, 2)
        let sessions = first.weeks.first?.days.first?.sessions ?? []
        let strengthSession = try XCTUnwrap(sessions.first { $0.items.contains { if case .strength = $0 { return true }; return false } })
        guard case let .strength(item) = strengthSession.items.first else {
            return XCTFail("strength item should be present")
        }
        XCTAssertEqual(item.sets.map(\.repTarget), [.exact(10), .exact(9), .exact(8)])
        XCTAssertEqual(item.sets.first?.load, .absoluteWeight(value: 60, unit: .kg))
        XCTAssertEqual(item.sets.first?.targetRIR, 2)
        let allStrengthSetIDs = sessions.flatMap { session in
            session.items.compactMap { item -> [UUID]? in
                if case let .strength(value) = item { return value.sets.map(\.id) }
                return nil
            }.flatMap { $0 }
        }
        XCTAssertEqual(allStrengthSetIDs.count, Set(allStrengthSetIDs).count)
        XCTAssertTrue(sessions.contains { $0.items.contains { if case .cardio = $0 { return true }; return false } })
    }
}
