#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

/// Regression coverage for "This Week is out of sync with reality": a past day
/// whose logged cardio was a Boxing session must read "Boxing", not the generic
/// "Easy aerobic" bucket the modality used to be flattened into.
struct WeeklyPlanModalityLabelTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var testNow: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 25; comps.hour = 12
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 1_750_000_000)
    }

    @Test func loggedBoxingDayReadsBoxingNotEasyAerobic() throws {
        let ctx = try makeContext()
        let now = testNow
        let yesterday = now.addingTimeInterval(-86_400)

        // A logged boxing session yesterday, no HR (so it classifies non-vigorous).
        let cardio = CardioWorkout(type: .boxing,
                                   start: yesterday.addingTimeInterval(-3600),
                                   end: yesterday.addingTimeInterval(-1800),
                                   source: .iphone)
        ctx.insert(cardio)
        let event = TrainingEvent.from(cardio: cardio)

        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        let plan = WeeklyPlan.generate(from: facts)

        let cal = Calendar.current
        let day = try #require(plan.days.first { cal.isDate($0.date, inSameDayAs: yesterday) },
                                "yesterday should be in the plan history window")
        #expect(day.label == "Boxing",
                       "A logged boxing day must carry its real modality, got '\(day.label)'")
        #expect(!day.label.localizedCaseInsensitiveContains("aerobic"),
                       "The generic aerobic bucket must not mask the real activity")
        let cardioSession = try #require(day.sessions.first { $0.kind == .easyAerobic || $0.kind == .moderateAerobic })
        #expect(cardioSession.label == "Boxing")
    }

    @Test func loggedRunDayReadsRun() throws {
        let ctx = try makeContext()
        let now = testNow
        let yesterday = now.addingTimeInterval(-86_400)

        let cardio = CardioWorkout(type: .run,
                                   start: yesterday.addingTimeInterval(-3600),
                                   end: yesterday.addingTimeInterval(-1800),
                                   avgHeartRate: 120, source: .iphone)
        ctx.insert(cardio)
        let event = TrainingEvent.from(cardio: cardio)

        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        let plan = WeeklyPlan.generate(from: facts)

        let cal = Calendar.current
        let day = try #require(plan.days.first { cal.isDate($0.date, inSameDayAs: yesterday) })
        #expect(day.label == "Run", "A logged run day should read its modality")
    }

    /// Future/prescribed cardio days have no logged modality to know yet, so they
    /// keep the generic bucket label — the fix is scoped to reconstructed history.
    @Test func futurePrescribedCardioKeepsGenericLabel() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let plan = WeeklyPlan.generate(from: facts)

        let futureCardio = plan.futureDays
            .flatMap(\.sessions)
            .filter { $0.kind == .easyAerobic || $0.kind == .moderateAerobic }
        for session in futureCardio {
            #expect(!["Boxing", "Run", "Walk", "Cycle", "Swim", "Row"].contains(session.label),
                           "Future cardio has no known modality; it keeps a generic label")
        }
    }
}
#endif
