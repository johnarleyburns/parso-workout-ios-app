import Foundation
import Testing
#if canImport(SwiftData)
import SwiftData
#endif
@testable import CadenceCore

struct TodayConsistencyTests {
    private var now: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12))!
    }

    @Test func sixCardioDaysPlanDoesNotBecomeRecoveryAfterFourVigorousDays() {
        let workouts = (1...4).map { day in
            CardioWorkout(type: .boxing, start: now.addingTimeInterval(-Double(day) * 86400 - 1800),
                          end: now.addingTimeInterval(-Double(day) * 86400), avgHeartRate: 170)
        }
        let facts = CoachFacts.make(from: workouts.map { TrainingEvent.from(cardio: $0) },
                                   goal: .hypertrophy, experience: .intermediate, now: now)
        #expect(facts.weeklyBalance.consecutiveHardDays == 0)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: .init(
            restPreference: .rolling(everyNDays: 3),
            allowsTwoADays: true))
        #expect(decision.primary.kind == .strength || decision.primary.isAerobic,
                      "Unmet chosen training targets must outrank hard-streak recovery")
        #expect(decision.warnings.first { $0.id == "consecutiveHardDays" } == nil,
                     "A streak that ended before today must not produce today's recovery note")
    }

    @Test func cardioNotDueOnceActualMinutesAreMetRegardlessOfCardioDays() {
        let workouts = (1...4).map { day in
            CardioWorkout(type: .boxing, start: now.addingTimeInterval(-Double(day) * 86400 - 3600),
                          end: now.addingTimeInterval(-Double(day) * 86400), avgHeartRate: 170)
        }
        let strength = (0...4).map { day in
            let end = now.addingTimeInterval(-Double(day) * 86400 - 7200)
            return TrainingEvent(id: UUID(), start: end.addingTimeInterval(-1800), end: end,
                                 kind: .strength(nil), source: .appStrength, completion: .completed)
        }
        let facts = CoachFacts.make(from: strength + workouts.map { TrainingEvent.from(cardio: $0) },
                                   goal: .hypertrophy, experience: .intermediate, now: now)
        let schedule = CoachSchedulePreferences(restPreference: .rolling(everyNDays: 3), allowsTwoADays: true)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: schedule)
        #expect(facts.weeklyBalance.strengthDays == 5)
        #expect(facts.weeklyBalance.cardioDays == 4)
        #expect(facts.weeklyBalance.consecutiveHardDays == 5)
        #expect(decision.observedFacts.first { $0.kind == .weeklyCardioDays }?.value == "4",
                       "Cardio days are reported as an observation, never against a target")
        #expect(decision.warnings.first { $0.id == "consecutiveHardDays" } != nil)
        #expect(facts.weeklyBalance.moderateEquivalentMinutes > 150)

        var explicitRest = schedule
        explicitRest.restPreference = .fixed(days: [.friday])
        let rest = CoachDecisionEngine.run(facts, schedulePreferences: explicitRest)
        #expect(rest.primary.kind == .rest || rest.primary.kind == .recovery,
                      "An explicit user-selected rest weekday remains their choice")
    }

    @Test func coachCreditEqualsWeeklyGuidelineCreditWithPersonalHRProfile() {
        let profile = CardioIntensityProfile.resolved(restingHR: 60, userEnteredMaximumHR: 180, age: 50)
        let cardio = CardioWorkout(type: .cycle, start: now.addingTimeInterval(-1800), end: now,
                                  avgHeartRate: 150)
        cardio.hrSamples = stride(from: 0, through: 1800, by: 30).map { HRSample(t: Double($0), bpm: 150) }
        let events = CoachSnapshotBuilder.trainingEvents(sessions: [], cardio: [cardio], assessments: [],
                                                         formula: .epley, userAge: 50,
                                                         cardioIntensityProfile: profile)
        let facts = CoachFacts.make(from: events, goal: .hypertrophy, experience: .intermediate, now: now)
        let weekly = WeeklyCardioAggregator.summarize([cardio], since: WeeklyStats.weekStart(now: now), profile: profile)
        #expect(abs(weekly.moderateEquivalentMinutes - 60) <= 0.01)
        #expect(abs(facts.weeklyBalance.moderateEquivalentMinutes - weekly.moderateEquivalentMinutes) <= 0.01)
        let decision = CoachDecisionEngine.run(facts)
        let observed = decision.observedFacts.first { $0.kind == .weeklyModerateEquivalentMinutes }
        #expect(observed?.value.contains("60") == true)
    }
}
