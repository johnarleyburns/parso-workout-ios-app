import XCTest
import SwiftData
@testable import CadenceCore

final class CoachSchedulePreferencesTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultPreferences() {
        let prefs = CoachSchedulePreferences.default
        XCTAssertEqual(prefs.strengthDaysPerWeek, 2)
        XCTAssertEqual(prefs.cardioDaysPerWeek, 3)
        if case .rolling(let n) = prefs.restPreference {
            XCTAssertEqual(n, 3)
        } else {
            XCTFail("Default rest preference should be rolling every 3")
        }
        XCTAssertFalse(prefs.allowsTwoADays)
        XCTAssertEqual(prefs.sameDayCardioTiming, .afterStrength)
    }

    // MARK: - Constraints

    func testStrengthDaysClamped() {
        let below = CoachSchedulePreferences(strengthDaysPerWeek: 1)
        XCTAssertEqual(below.strengthDaysPerWeek, 2, "Should clamp to minimum 2")

        let above = CoachSchedulePreferences(strengthDaysPerWeek: 6)
        XCTAssertEqual(above.strengthDaysPerWeek, 5, "Should clamp to maximum 5")

        let valid = CoachSchedulePreferences(strengthDaysPerWeek: 4)
        XCTAssertEqual(valid.strengthDaysPerWeek, 4)
    }

    func testCardioDaysClamped() {
        let below = CoachSchedulePreferences(cardioDaysPerWeek: -1)
        XCTAssertEqual(below.cardioDaysPerWeek, 0, "Should clamp to minimum 0")

        let above = CoachSchedulePreferences(cardioDaysPerWeek: 8)
        XCTAssertEqual(above.cardioDaysPerWeek, 7, "Should clamp to maximum 7")

        let valid = CoachSchedulePreferences(cardioDaysPerWeek: 5)
        XCTAssertEqual(valid.cardioDaysPerWeek, 5)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let prefs = CoachSchedulePreferences(
            strengthDaysPerWeek: 3,
            cardioDaysPerWeek: 4,
            restPreference: .fixed(days: [.saturday, .sunday]),
            allowsTwoADays: true,
            sameDayCardioTiming: .separateLater
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(CoachSchedulePreferences.self, from: data)
        XCTAssertEqual(decoded.strengthDaysPerWeek, 3)
        XCTAssertEqual(decoded.cardioDaysPerWeek, 4)
        XCTAssertEqual(decoded.restPreference, .fixed(days: [.saturday, .sunday]))
        XCTAssertTrue(decoded.allowsTwoADays)
        XCTAssertEqual(decoded.sameDayCardioTiming, .separateLater)
    }

    func testRollingRestRoundTrip() throws {
        let prefs = CoachSchedulePreferences(restPreference: .rolling(everyNDays: 4))
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(CoachSchedulePreferences.self, from: data)
        XCTAssertEqual(decoded.restPreference, .rolling(everyNDays: 4))
    }

    // MARK: - Weekday

    func testWeekdayFromDate() {
        let cal = Calendar.current
        // Sunday = 1 for Calendar.current .weekday on en_US
        var sundayComps = DateComponents(year: 2026, month: 1, day: 4, hour: 12) // Sunday
        if let sunDate = cal.date(from: sundayComps) {
            XCTAssertEqual(Weekday(from: sunDate, calendar: cal), .sunday)
        }

        var mondayComps = DateComponents(year: 2026, month: 1, day: 5, hour: 12) // Monday
        if let monDate = cal.date(from: mondayComps) {
            XCTAssertEqual(Weekday(from: monDate, calendar: cal), .monday)
        }

        var saturdayComps = DateComponents(year: 2026, month: 1, day: 10, hour: 12) // Saturday
        if let satDate = cal.date(from: saturdayComps) {
            XCTAssertEqual(Weekday(from: satDate, calendar: cal), .saturday)
        }
    }

    func testWeekdayAllCases() {
        XCTAssertEqual(Weekday.allCases.count, 7)
        XCTAssertEqual(Weekday.allCases.map(\.rawValue).sorted(), [1, 2, 3, 4, 5, 6, 7])
    }

    // MARK: - With helpers

    func testWithStrengthDays() {
        let prefs = CoachSchedulePreferences.default.withStrengthDays(4)
        XCTAssertEqual(prefs.strengthDaysPerWeek, 4)
        XCTAssertEqual(prefs.cardioDaysPerWeek, 3) // unchanged
    }

    func testWithCardioDays() {
        let prefs = CoachSchedulePreferences.default.withCardioDays(5)
        XCTAssertEqual(prefs.cardioDaysPerWeek, 5)
    }

    func testWithTwoADays() {
        let prefs = CoachSchedulePreferences.default.withTwoADays(true)
        XCTAssertTrue(prefs.allowsTwoADays)
    }

    func testWithSameDayCardioTiming() {
        let prefs = CoachSchedulePreferences.default.withSameDayCardioTiming(.separateLater)
        XCTAssertEqual(prefs.sameDayCardioTiming, .separateLater)
    }

    // MARK: - Decision engine uses strength target 2

    func testDecisionEngineDynamicStrengthTargetInObservedFacts() throws {
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: Date())
        let prefs = CoachSchedulePreferences(strengthDaysPerWeek: 3)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)
        // With 0/3 strength days, the target text should reflect the dynamic target
        let fact = decision.observedFacts.first { $0.kind == .weeklyStrengthDays }
        XCTAssertNotNil(fact)
        XCTAssertTrue(fact!.value.contains("3"), "Should use dynamic target 3")
    }

    // MARK: - Decision engine with met strength needs cardio

    func testDecisionEngineMetStrengthPrefersCardio() throws {
        let ctx = try ModelContext(CadenceStore.makeModelContainer(inMemory: true))
        let now = Date()

        func makeStrength(_ name: String, _ muscles: [String], _ daysAgo: Double, _ sets: Int) throws -> TrainingEvent {
            let date = now.addingTimeInterval(-daysAgo * 86400)
            let session = try WorkoutRepository.createSession(date: date.addingTimeInterval(-600), in: ctx)
            let ex = try WorkoutRepository.findOrCreateExercise(named: name, primaryMuscles: muscles, in: ctx)
            for _ in 0..<sets {
                _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5, rpe: 8, in: ctx)
            }
            session.endedAt = date
            return TrainingEvent.from(session: session)!
        }

        let s1 = try makeStrength("Squat", ["quadriceps"], 1, 3)
        let s2 = try makeStrength("Bench", ["chest"], 3, 3)

        let facts = CoachFacts.make(from: [s1, s2], goal: .strength, experience: .intermediate, now: now)
        // With 2 strength days, default target of 2 is met
        let prefs = CoachSchedulePreferences(strengthDaysPerWeek: 2)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)
        XCTAssertTrue(decision.primary.isAerobic, "With strength target met and no cardio, primary should be aerobic. Got: \(decision.primary.kind)")
    }

    // MARK: - Decision engine with higher strength target still needs strength (but aerobic deficit wins first)

    func testDecisionEngineHigherTargetObservedFactsReflectTarget() throws {
        let ctx = try ModelContext(CadenceStore.makeModelContainer(inMemory: true))
        let now = Date()

        func makeStrength(_ name: String, _ muscles: [String], _ daysAgo: Double, _ sets: Int) throws -> TrainingEvent {
            let date = now.addingTimeInterval(-daysAgo * 86400)
            let session = try WorkoutRepository.createSession(date: date.addingTimeInterval(-600), in: ctx)
            let ex = try WorkoutRepository.findOrCreateExercise(named: name, primaryMuscles: muscles, in: ctx)
            for _ in 0..<sets {
                _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5, rpe: 8, in: ctx)
            }
            session.endedAt = date
            return TrainingEvent.from(session: session)!
        }

        let s1 = try makeStrength("Squat", ["quadriceps"], 1, 3)
        let s2 = try makeStrength("Bench", ["chest"], 3, 3)

        let facts = CoachFacts.make(from: [s1, s2], goal: .strength, experience: .intermediate, now: now)
        let prefs = CoachSchedulePreferences(strengthDaysPerWeek: 5)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)

        let fact = decision.observedFacts.first { $0.kind == .weeklyStrengthDays }
        XCTAssertNotNil(fact)
        XCTAssertTrue(fact!.value.contains("5"), "Should use dynamic target 5. Got: \(fact!.value)")
    }

    // MARK: - Cardio day target independent of minutes

    func testCardioDayTargetIndependentOfMinutes() throws {
        let context = try ModelContext(CadenceStore.makeModelContainer(inMemory: true))
        let now = Date()
        let cal = Calendar.current

        // Create a cardio event: 180 min (enough for minutes target)
        func makeCardio(_ type: CardioType, _ daysAgo: Double, _ minutes: Double) -> TrainingEvent {
            let date = now.addingTimeInterval(-daysAgo * 86400)
            let cardio = CardioWorkout(type: type, start: date.addingTimeInterval(-minutes * 60),
                                        end: date, avgHeartRate: 135, source: .iphone)
            context.insert(cardio)
            return TrainingEvent.from(cardio: cardio)
        }

        let c1 = makeCardio(.run, 1, 180) // 180 mod-eq min on 1 day

        let facts = CoachFacts.make(from: [c1], goal: .strength, experience: .intermediate, now: now)
        XCTAssertGreaterThanOrEqual(facts.weeklyBalance.moderateEquivalentMinutes, 150,
                                     "Minutes target should be met")
        XCTAssertEqual(facts.weeklyBalance.cardioDays, 1,
                       "Cardio days should be distinct days, not minutes")

        // With cardioDays target = 3 and only 1 day done, cardio should still be needed
        let prefs = CoachSchedulePreferences(strengthDaysPerWeek: 2, cardioDaysPerWeek: 3)
        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: prefs)
        let futureSessions = plan.futureDays.flatMap(\.sessions)
        let hasCardio = futureSessions.contains { $0.kind == .moderateAerobic || $0.kind == .easyAerobic }
        XCTAssertTrue(hasCardio, "Should still plan cardio days even though minutes target is met")

        // But with 0/2 strength and zero cardio days, strength should still win for the decision
        // This test just verifies cardio day counting is independent from minutes
    }

    // MARK: - Two-a-days gating

    func testTwoADaysDisabledNoDoubleSession() throws {
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: Date())
        let prefs = CoachSchedulePreferences(strengthDaysPerWeek: 2, cardioDaysPerWeek: 3,
                                              allowsTwoADays: false)
        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: prefs)
        let futureDays = plan.futureDays

        for day in futureDays {
            let strengthCount = day.sessions.filter { $0.kind == .strength }.count
            let cardioCount = day.sessions.filter {
                $0.kind == .moderateAerobic || $0.kind == .easyAerobic
            }.count
            XCTAssertTrue(strengthCount + cardioCount <= 1,
                          "Without two-a-days, at most one workout per day. Day: \(day.date)")
        }
    }

    func testTwoADaysEnabledAllowsDoubleSession() throws {
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: Date())
        let prefs = CoachSchedulePreferences(strengthDaysPerWeek: 2, cardioDaysPerWeek: 3,
                                              allowsTwoADays: true)
        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: prefs)
        let futureDays = plan.futureDays

        // At least one day should have both strength and cardio
        let hasDoubleSession = futureDays.contains { day in
            let hasStrength = day.sessions.contains { $0.kind == .strength }
            let hasCardio = day.sessions.contains {
                $0.kind == .moderateAerobic || $0.kind == .easyAerobic
            }
            return hasStrength && hasCardio
        }
        XCTAssertTrue(hasDoubleSession, "With two-a-days enabled, some days should have strength + cardio")
    }

    // MARK: - Cardio timing note

    func testTwoADayCardioTimingNote() throws {
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: Date())

        let afterStrength = CoachSchedulePreferences(strengthDaysPerWeek: 2, cardioDaysPerWeek: 5,
                                                      allowsTwoADays: true,
                                                      sameDayCardioTiming: .afterStrength)
        let planAS = WeeklyPlan.generate(from: facts, schedulePreferences: afterStrength)
        let cardioWithNote = planAS.futureDays.flatMap(\.sessions).filter {
            ($0.kind == .moderateAerobic || $0.kind == .easyAerobic) && $0.timingNote != nil
        }
        XCTAssertFalse(cardioWithNote.isEmpty, "Should have timing notes on same-day cardio")

        let separate = CoachSchedulePreferences(strengthDaysPerWeek: 2, cardioDaysPerWeek: 5,
                                                 allowsTwoADays: true,
                                                 sameDayCardioTiming: .separateLater)
        let planSep = WeeklyPlan.generate(from: facts, schedulePreferences: separate)
        let separateNotes = planSep.futureDays.flatMap(\.sessions).filter {
            ($0.kind == .moderateAerobic || $0.kind == .easyAerobic) && $0.timingNote == "later in the day"
        }
        XCTAssertFalse(separateNotes.isEmpty, "Should have 'later in the day' notes")
    }

    // MARK: - Fixed rest days

    func testFixedRestSaturdayAndSunday() throws {
        let prefs = CoachSchedulePreferences(
            strengthDaysPerWeek: 2,
            cardioDaysPerWeek: 3,
            restPreference: .fixed(days: [.saturday, .sunday])
        )
        let encoded = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(CoachSchedulePreferences.self, from: encoded)
        XCTAssertEqual(decoded.restPreference, .fixed(days: [.saturday, .sunday]))
    }

    func testRollingRestEveryThreeDays() throws {
        let prefs = CoachSchedulePreferences(
            strengthDaysPerWeek: 2,
            cardioDaysPerWeek: 3,
            restPreference: .rolling(everyNDays: 3)
        )
        let encoded = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(CoachSchedulePreferences.self, from: encoded)
        XCTAssertEqual(decoded.restPreference, .rolling(everyNDays: 3))
    }

    // MARK: - Observed facts use dynamic targets

    func testObservedFactsUseDynamicStrengthTarget() throws {
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: Date())
        let prefs = CoachSchedulePreferences(strengthDaysPerWeek: 4)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)

        let strengthFact = decision.observedFacts.first { $0.kind == .weeklyStrengthDays }
        XCTAssertNotNil(strengthFact)
        XCTAssertTrue(strengthFact!.value.contains("4"),
                      "Strength target should be 4. Got: \(strengthFact!.value)")
    }

    // MARK: - WeeklyPlan extends horizon beyond +6

    func testWeeklyPlanIncludesNextWeek() throws {
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: Date())
        let plan = WeeklyPlan.generate(from: facts)

        let nextWeek = plan.nextWeekDays
        XCTAssertFalse(nextWeek.isEmpty, "Should include next week days")

        // Verify all next week days are in the future
        let cal = Calendar.current
        let nextWeekStart = cal.date(byAdding: .day, value: 7,
                                      to: WeeklyStats.weekStart(now: Date())) ?? Date()
        for day in nextWeek {
            XCTAssertTrue(day.date >= nextWeekStart, "Next week day should be in next week")
        }
    }

    // MARK: - WeeklyPlan planned properties

    func testWeeklyPlanPlannedProperties() throws {
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: Date())
        let plan = WeeklyPlan.generate(from: facts)

        XCTAssertNotNil(plan.today)
        XCTAssertNotNil(plan.tomorrow)
        XCTAssertFalse(plan.futureDays.isEmpty)
        XCTAssertFalse(plan.plannedCurrentWeekSessions.isEmpty)
        // next week should also be planned
        XCTAssertFalse(plan.nextWeekDays.isEmpty)
    }

    // MARK: - Weekday display

    func testWeekdayDisplayNames() {
        XCTAssertEqual(Weekday.sunday.displayName, "Sun")
        XCTAssertEqual(Weekday.monday.displayName, "Mon")
        XCTAssertEqual(Weekday.friday.displayName, "Fri")
        XCTAssertEqual(Weekday.saturday.displayName, "Sat")
    }
}
