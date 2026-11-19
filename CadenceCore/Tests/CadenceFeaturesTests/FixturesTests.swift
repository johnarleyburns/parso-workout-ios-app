#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadenceFixtures

/// Phase 0 smoke: proves the lifted fixture catalog builds a real in-memory
/// SwiftData graph under `swift test`, exactly as the old UI seed did — the whole
/// point of moving them out of the app target.
@MainActor
struct FixturesTests {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test func priorBenchSeedsThreeSets() throws {
        let ctx = try makeContext()
        Fixtures.priorBench(into: ctx)
        let sets = try ctx.fetch(FetchDescriptor<SetEntry>())
        #expect(sets.count == 3)
        #expect(sets.allSatisfy { $0.weight == 100 })
    }

    @Test func historyMixedSeedsStrengthAndCardio() throws {
        let ctx = try makeContext()
        Fixtures.historyMixed(into: ctx)
        let sessions = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        let cardio = try ctx.fetch(FetchDescriptor<CardioWorkout>())
        #expect(sessions.count == 5)
        #expect(cardio.count == 1)
    }

    @Test func historyPartnerSessionAttributesOneSetToSam() throws {
        let ctx = try makeContext()
        Fixtures.historyPartnerSession(into: ctx)
        let people = try ctx.fetch(FetchDescriptor<Person>())
        #expect(people.contains { $0.name == "Sam" })
        let sets = try ctx.fetch(FetchDescriptor<SetEntry>())
        #expect(sets.count == 3)
        #expect(sets.filter { $0.performedBy != nil }.count == 1)
    }

    @Test func coachWednesdayCompleteSeedsTodayStrengthAndCardio() throws {
        let ctx = try makeContext()
        Fixtures.coachWednesdayComplete(into: ctx)
        let cal = Calendar.current
        let sessions = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        let cardio = try ctx.fetch(FetchDescriptor<CardioWorkout>())
        #expect(sessions.contains { cal.isDateInToday($0.date) })
        #expect(cardio.contains { cal.isDateInToday($0.start) })
    }

    @Test func twoADayPreferenceJSONDecodes() throws {
        let ctx = try makeContext()
        let defaults = UserDefaults(suiteName: "FixturesTests.twoADay")!
        defaults.removePersistentDomain(forName: "FixturesTests.twoADay")
        Fixtures.coachTwoADayStrengthDone(into: ctx, defaults: defaults)
        let raw = defaults.data(forKey: "settings.coachSchedulePreferences")
        #expect(raw != nil)
        let decoded = try JSONDecoder().decode(CoachSchedulePreferences.self, from: raw!)
        #expect(decoded.allowsTwoADays)
    }
}
#endif
