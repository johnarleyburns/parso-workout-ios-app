import XCTest
import SwiftData
@testable import CadenceCore

/// Regression tests mirroring the `Cladiron-Export-2026-07-14` profile that
/// surfaced the "coach suggests, it does not proscribe" bug cluster: userAge 50,
/// 5 strength + 6 cardio days/week, two-a-days on, fixed Sunday rest. The real
/// export is personal health data and stays out of the repo (git-ignored); these
/// fixtures reproduce its sessions synthetically, including real avg/max HR.
final class SameDayLoadRegressionTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    /// Fixed Wednesday 2026-07-15 18:00 — the day the user did HIIT (Tabata)
    /// then boxing and was still prescribed "Easy cycle."
    private var testNow: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 15
        comps.hour = 18; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 1_784_000_000)
    }

    private var exportPrefs: CoachSchedulePreferences {
        CoachSchedulePreferences(
            strengthDaysPerWeek: 5,
            cardioDaysPerWeek: 6,
            restPreference: .fixed(days: [.sunday]),
            allowsTwoADays: true,
            sameDayCardioTiming: .separateLater)
    }

    private func cardioEvent(_ ctx: ModelContext, type: CardioType, start: Date,
                             minutes: Double, avgHR: Double? = nil,
                             maxHR: Double? = nil) throws -> TrainingEvent {
        let cardio = CardioWorkout(type: type, start: start,
                                   end: start.addingTimeInterval(minutes * 60),
                                   avgHeartRate: avgHR, maxHeartRate: maxHR, source: .iphone)
        ctx.insert(cardio)
        try ctx.save()
        return TrainingEvent.from(cardio: cardio, userAge: 50)
    }

    /// HIIT (no HR) + boxing (avg 139 / peak 170) earlier today, age 50.
    private func todayHIITPlusBoxing(_ ctx: ModelContext) throws -> [TrainingEvent] {
        let hiit = try cardioEvent(ctx, type: .hiit,
                                   start: testNow.addingTimeInterval(-7 * 3600), minutes: 25)
        let boxing = try cardioEvent(ctx, type: .boxing,
                                     start: testNow.addingTimeInterval(-4 * 3600), minutes: 33,
                                     avgHR: 139, maxHR: 170)
        return [hiit, boxing]
    }

    /// (a)+(b) After same-day HIIT + boxing, the primary must not be another
    /// aerobic session ("Easy cycle"), and strength must remain selectable.
    func testHIITPlusBoxingDayDoesNotPrescribeMoreCardio() throws {
        let ctx = try makeContext()
        let events = try todayHIITPlusBoxing(ctx)
        let facts = CoachFacts.make(from: events, goal: .hypertrophy,
                                    experience: .intermediate, now: testNow)

        let decision = CoachDecisionEngine.run(facts, schedulePreferences: exportPrefs)

        XCTAssertFalse(decision.primary.isAerobic,
                       "After HIIT + boxing today the coach must not rank more cardio first. Got: \(decision.primary.id)")
        // (c) Strength is never suppressed by same-day cardio: with 0/5 strength
        // days this week, strength should be the primary.
        XCTAssertEqual(decision.primary.kind, .strength,
                       "Strength (0/5 this week) should outrank redundant cardio. Got: \(decision.primary.kind)")
    }

    /// (d) The free "already trained hard today" insight surfaces with a
    /// resolvable citation (HARD RULE).
    func testSameDayLoadInsightSurfacesWithCitation() throws {
        let ctx = try makeContext()
        let events = try todayHIITPlusBoxing(ctx)
        let facts = CoachFacts.make(from: events, goal: .hypertrophy,
                                    experience: .intermediate, now: testNow)

        let insight = SameDayLoadInsight.insight(facts: facts)
        XCTAssertNotNil(insight)
        XCTAssertTrue(insight?.message.contains("HIIT") ?? false, "Names the modalities")
        XCTAssertTrue(insight?.message.contains("Boxing") ?? false, "Names the modalities")
        XCTAssertTrue(insight?.message.contains("2 intense sessions") ?? false)
        // Citation must resolve through the registry (never a raw id).
        let resolved = CitationRegistry.citation(forId: insight?.citation.id ?? "")
        XCTAssertNotNil(resolved)
    }

    /// No intense (or repeated) cardio today → no insight; the coach stays quiet.
    func testNoInsightWithoutSameDayIntenseLoad() throws {
        let ctx = try makeContext()
        let walk = try cardioEvent(ctx, type: .walk,
                                   start: testNow.addingTimeInterval(-4 * 3600), minutes: 40,
                                   avgHR: 96, maxHR: 104)
        let facts = CoachFacts.make(from: [walk], goal: .hypertrophy,
                                    experience: .intermediate, now: testNow)
        XCTAssertNil(SameDayLoadInsight.insight(facts: facts))
    }
}
