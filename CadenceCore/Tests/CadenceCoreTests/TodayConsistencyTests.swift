import XCTest
import SwiftData
@testable import CadenceCore

final class TodayConsistencyTests: XCTestCase {
    private var now: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12))!
    }

    func testSixCardioDaysPlanDoesNotBecomeRecoveryAfterFourVigorousDays() {
        let workouts = (1...4).map { day in
            CardioWorkout(type: .boxing, start: now.addingTimeInterval(-Double(day) * 86400 - 1800),
                          end: now.addingTimeInterval(-Double(day) * 86400), avgHeartRate: 170)
        }
        let facts = CoachFacts.make(from: workouts.map { TrainingEvent.from(cardio: $0) },
                                   goal: .hypertrophy, experience: .intermediate, now: now)
        XCTAssertEqual(facts.weeklyBalance.consecutiveHardDays, 4)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: .init(
            strengthDaysPerWeek: 5, cardioDaysPerWeek: 6, restPreference: .rolling(everyNDays: 3),
            allowsTwoADays: true))
        XCTAssertTrue(decision.primary.kind == .strength || decision.primary.isAerobic,
                      "Unmet chosen training targets must outrank hard-streak recovery")
    }

    func testDueCardioDayStillCountsAfterMinuteAndStrengthGoalsAreMet() {
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
        let schedule = CoachSchedulePreferences(strengthDaysPerWeek: 5, cardioDaysPerWeek: 6,
                                                 restPreference: .rolling(everyNDays: 3), allowsTwoADays: true)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: schedule)
        XCTAssertEqual(facts.weeklyBalance.strengthDays, 5)
        XCTAssertEqual(facts.weeklyBalance.cardioDays, 4)
        XCTAssertEqual(facts.weeklyBalance.consecutiveHardDays, 4)
        XCTAssertTrue(decision.primary.isAerobic, "Cardio frequency remains due even after minute target is met")
        XCTAssertEqual(decision.observedFacts.first { $0.kind == .weeklyCardioDays }?.value, "4/6")
        XCTAssertNotNil(decision.warnings.first { $0.id == "consecutiveHardDays" })
        XCTAssertGreaterThan(facts.weeklyBalance.moderateEquivalentMinutes, 150)
        if case .planComplete = decision.planAdherence { XCTFail("Today's cardio is still due") }

        var explicitRest = schedule
        explicitRest.restPreference = .fixed(days: [.friday])
        let rest = CoachDecisionEngine.run(facts, schedulePreferences: explicitRest)
        XCTAssertTrue(rest.primary.kind == .rest || rest.primary.kind == .recovery,
                      "An explicit user-selected rest weekday remains their choice")
    }

    func testCoachCreditEqualsWeeklyGuidelineCreditWithPersonalHRProfile() {
        let profile = CardioIntensityProfile.resolved(restingHR: 60, userEnteredMaximumHR: 180, age: 50)
        let cardio = CardioWorkout(type: .cycle, start: now.addingTimeInterval(-1800), end: now,
                                  avgHeartRate: 150)
        cardio.hrSamples = stride(from: 0, through: 1800, by: 30).map { HRSample(t: Double($0), bpm: 150) }
        let events = CoachSnapshotBuilder.trainingEvents(sessions: [], cardio: [cardio], assessments: [],
                                                         formula: .epley, userAge: 50,
                                                         cardioIntensityProfile: profile)
        let facts = CoachFacts.make(from: events, goal: .hypertrophy, experience: .intermediate, now: now)
        let weekly = WeeklyCardioAggregator.summarize([cardio], since: WeeklyStats.weekStart(now: now), profile: profile)
        XCTAssertEqual(weekly.moderateEquivalentMinutes, 60, accuracy: 0.01)
        XCTAssertEqual(facts.weeklyBalance.moderateEquivalentMinutes, weekly.moderateEquivalentMinutes, accuracy: 0.01)
        let decision = CoachDecisionEngine.run(facts)
        let observed = decision.observedFacts.first { $0.kind == .weeklyModerateEquivalentMinutes }
        XCTAssertTrue(observed?.value.contains("60") == true)
    }
}
