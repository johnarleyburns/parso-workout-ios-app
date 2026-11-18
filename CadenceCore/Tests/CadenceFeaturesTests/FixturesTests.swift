import XCTest
import SwiftData
import CadenceCore
import CadenceFixtures

/// Phase 0 smoke: proves the lifted fixture catalog builds a real in-memory
/// SwiftData graph under `swift test`, exactly as the old UI seed did — the whole
/// point of moving them out of the app target.
@MainActor
final class FixturesTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    func testPriorBenchSeedsThreeSets() throws {
        let ctx = try makeContext()
        Fixtures.priorBench(into: ctx)
        let sets = try ctx.fetch(FetchDescriptor<SetEntry>())
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { $0.weight == 100 })
    }

    func testHistoryMixedSeedsStrengthAndCardio() throws {
        let ctx = try makeContext()
        Fixtures.historyMixed(into: ctx)
        let sessions = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        let cardio = try ctx.fetch(FetchDescriptor<CardioWorkout>())
        XCTAssertEqual(sessions.count, 5)
        XCTAssertEqual(cardio.count, 1)
    }

    func testHistoryPartnerSessionAttributesOneSetToSam() throws {
        let ctx = try makeContext()
        Fixtures.historyPartnerSession(into: ctx)
        let people = try ctx.fetch(FetchDescriptor<Person>())
        XCTAssertTrue(people.contains { $0.name == "Sam" })
        let sets = try ctx.fetch(FetchDescriptor<SetEntry>())
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets.filter { $0.performedBy != nil }.count, 1)
    }

    func testCoachWednesdayCompleteSeedsTodayStrengthAndCardio() throws {
        let ctx = try makeContext()
        Fixtures.coachWednesdayComplete(into: ctx)
        let cal = Calendar.current
        let sessions = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        let cardio = try ctx.fetch(FetchDescriptor<CardioWorkout>())
        XCTAssertTrue(sessions.contains { cal.isDateInToday($0.date) })
        XCTAssertTrue(cardio.contains { cal.isDateInToday($0.start) })
    }

    func testTwoADayPreferenceJSONDecodes() throws {
        let ctx = try makeContext()
        let defaults = UserDefaults(suiteName: "FixturesTests.twoADay")!
        defaults.removePersistentDomain(forName: "FixturesTests.twoADay")
        Fixtures.coachTwoADayStrengthDone(into: ctx, defaults: defaults)
        let raw = defaults.data(forKey: "settings.coachSchedulePreferences")
        XCTAssertNotNil(raw)
        let decoded = try JSONDecoder().decode(CoachSchedulePreferences.self, from: raw!)
        XCTAssertTrue(decoded.allowsTwoADays)
    }
}
