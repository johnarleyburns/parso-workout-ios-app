import XCTest
import SwiftData
@testable import CadenceCore

final class CoachFactsTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var testNow: Date {
        // Fixed absolute Thursday (2026-06-25 12:00) — deterministic, no wall-clock drift.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 25
        comps.hour = 12; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 1_750_000_000)
    }

    private func makeStrengthEvent(context: ModelContext, name: String, primaryMuscles: [String],
                                    secondaryMuscles: [String] = [], weight: Double, reps: Int, rpe: Double?,
                                    date: Date) throws -> TrainingEvent {
        let session = try WorkoutRepository.createSession(date: date.addingTimeInterval(-600), in: context)
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: name, primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: weight, reps: reps, rpe: rpe, completedAt: date, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: weight, reps: reps, rpe: rpe, completedAt: date, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: weight, reps: reps, rpe: rpe, completedAt: date, in: context)
        session.endedAt = date
        return TrainingEvent.from(session: session)!
    }

    private func makeCardioEvent(context: ModelContext, type: CardioType, start: Date, duration: TimeInterval,
                                  avgHR: Double?) -> TrainingEvent {
        let cardio = CardioWorkout(type: type, start: start, end: start.addingTimeInterval(duration),
                                    avgHeartRate: avgHR, source: .iphone)
        context.insert(cardio)
        return TrainingEvent.from(cardio: cardio)
    }

    // MARK: - Rolling windows

    func testRolling72hWindowIncludesRecentEvents() throws {
        let ctx = try makeContext()
        let now = testNow
        let event = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                           weight: 100, reps: 5, rpe: 8, date: now.addingTimeInterval(-3600))
        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(facts.rolling72hCompletedEvents.count, 1)
    }

    func testRolling72hWindowExcludesOldEvents() throws {
        let ctx = try makeContext()
        let now = testNow
        let event = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                           weight: 100, reps: 5, rpe: 8, date: now.addingTimeInterval(-80 * 3600))
        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(facts.rolling72hCompletedEvents.count, 0)
    }

    func testRolling7dWindowKeepsSundayOnMonday() throws {
        let ctx = try makeContext()
        let now = testNow
        let sundayEvent = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                                 weight: 100, reps: 5, rpe: 8, date: now.addingTimeInterval(-5 * 86400))
        let facts = CoachFacts.make(from: [sundayEvent], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(facts.rolling7dCompletedEvents.count, 1)
    }

    func testEventExactly7dAgoDropsOut() throws {
        let ctx = try makeContext()
        let now = testNow
        let exactEvent = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                                weight: 100, reps: 5, rpe: 8,
                                                date: now.addingTimeInterval(-7 * 86400 - 1))
        let facts = CoachFacts.make(from: [exactEvent], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(facts.rolling7dCompletedEvents.count, 0)
    }

    func testNowIsInjectable() throws {
        let ctx = try makeContext()
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                            weight: 100, reps: 5, rpe: 8,
                                            date: fixedNow.addingTimeInterval(-3600))
        let facts = CoachFacts.make(from: [recent], goal: .strength, experience: .intermediate, now: fixedNow)
        XCTAssertEqual(facts.rolling72hCompletedEvents.count, 1)
    }

    /// Rolling windows must be chronological (ascending by end) regardless of the
    /// order Home supplies events, so downstream "last X" lookups are deterministic.
    func testRolling72hCompletedEventsAreSortedAscendingByEnd() throws {
        let ctx = try makeContext()
        let now = testNow
        let eA = makeCardioEvent(context: ctx, type: .walk, start: now.addingTimeInterval(-7200),
                                 duration: 1800, avgHR: 110)   // end = now - 5400
        let eB = makeCardioEvent(context: ctx, type: .run, start: now.addingTimeInterval(-3600),
                                 duration: 1800, avgHR: 150)   // end = now - 1800
        let eC = makeCardioEvent(context: ctx, type: .cycle, start: now.addingTimeInterval(-10800),
                                 duration: 1800, avgHR: 120)   // end = now - 9000
        // Scrambled input order.
        let facts = CoachFacts.make(from: [eB, eC, eA], goal: .strength, experience: .intermediate, now: now)
        let ends = facts.rolling72hCompletedEvents.map(\.end)
        XCTAssertEqual(ends, ends.sorted(), "rolling 72h events must be sorted ascending by end")
        XCTAssertEqual(facts.rolling72hCompletedEvents.last?.end, eB.end, "newest is last")
    }

    /// This week's balance must exclude future-dated events.
    func testThisWeekBalanceExcludesFutureEvents() throws {
        let ctx = try makeContext()
        let now = testNow
        let pastWalk = makeCardioEvent(context: ctx, type: .walk, start: now.addingTimeInterval(-5400),
                                       duration: 1800, avgHR: nil)  // moderate ⇒ 30 mod-eq
        let futureRun = makeCardioEvent(context: ctx, type: .run, start: now.addingTimeInterval(82800),
                                        duration: 3600, avgHR: 160) // vigorous ⇒ 120 if wrongly counted
        let facts = CoachFacts.make(from: [futureRun, pastWalk], goal: .strength, experience: .intermediate, now: now)
        let modEquiv = facts.weeklyBalance.moderateEquivalentMinutes
        XCTAssertGreaterThan(modEquiv, 0, "past walk should count")
        XCTAssertLessThanOrEqual(modEquiv, 35, "future run must be excluded; got \(modEquiv) min")
    }

    // MARK: - Moderate-equivalent minutes

    func testModerateEquivalentMinutes() throws {
        let ctx = try makeContext()
        let now = testNow
        let run = makeCardioEvent(context: ctx, type: .run, start: now.addingTimeInterval(-7200),
                                   duration: 1800, avgHR: 160)
        let walk = makeCardioEvent(context: ctx, type: .walk, start: now.addingTimeInterval(-3600),
                                    duration: 3600, avgHR: 100)

        let facts = CoachFacts.make(from: [run, walk], goal: .strength, experience: .intermediate, now: now)
        XCTAssertGreaterThan(facts.weeklyBalance.moderateEquivalentMinutes, 0)
        XCTAssertGreaterThan(facts.weeklyBalance.vigorousMinutes, 0)
    }

    func testMissingHRIntensityIsLowConfidence() throws {
        let ctx = try makeContext()
        let now = testNow
        let walk = makeCardioEvent(context: ctx, type: .walk, start: now.addingTimeInterval(-3600),
                                    duration: 1800, avgHR: nil)
        let facts = CoachFacts.make(from: [walk], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(facts.weeklyBalance.dataCompleteness, .moderate)
    }

    func testModerateEquivalentMinutes_respectsMondayWeekBoundary() throws {
        let ctx = try makeContext()
        let cal = Calendar.current
        var comps = DateComponents(year: 2026, month: 6, day: 23, hour: 12)
        let now = cal.date(from: comps)!
        let weekStart = WeeklyStats.weekStart(now: now)
        let prevDay = cal.date(byAdding: .day, value: -1, to: weekStart)!

        let thisWeekEvent = makeCardioEvent(context: ctx, type: .walk, start: weekStart.addingTimeInterval(3600),
                                             duration: 1123, avgHR: nil)
        let prevWeekEvent = makeCardioEvent(context: ctx, type: .run, start: prevDay.addingTimeInterval(3600),
                                             duration: 7200, avgHR: 160)

        let facts = CoachFacts.make(from: [thisWeekEvent, prevWeekEvent], goal: .strength,
                                     experience: .intermediate, now: now)
        let modEquiv = Int(facts.weeklyBalance.moderateEquivalentMinutes)
        XCTAssertLessThanOrEqual(modEquiv, 25, "Should exclude previous-week event; got \(modEquiv) min")
        XCTAssertGreaterThan(modEquiv, 0, "Should include this-week event")
    }

    // MARK: - Recovery state

    func testRecoveryWindowBlocksExactExercise() throws {
        let ctx = try makeContext()
        let now = testNow
        let event = try makeStrengthEvent(context: ctx, name: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"],
                                           weight: 140, reps: 5, rpe: 9, date: now.addingTimeInterval(-600))
        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        XCTAssertNotNil(facts.recovery.byExercise["Deadlift"])
        let window = facts.recovery.byExercise["Deadlift"]!
        XCTAssertTrue(window.hardEligibleAt > now)
    }

    func testHighFatigueExtendsRecoveryWindow() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-1200), in: ctx)
        let deadlift = try WorkoutRepository.findOrCreateExercise(
            named: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"], in: ctx)
        for _ in 0..<8 {
            _ = try WorkoutRepository.addSet(to: session, exercise: deadlift, weightKg: 140, reps: 3, rpe: 10, in: ctx)
        }
        session.endedAt = now.addingTimeInterval(-600)

        let event = TrainingEvent.from(session: session)
        let facts = CoachFacts.make(from: [event!], goal: .strength, experience: .intermediate, now: now)
        let window = facts.recovery.byExercise["Deadlift"]
        XCTAssertNotNil(window)
        let hours = window!.hardEligibleAt.timeIntervalSince(window!.lastExposedAt) / 3600
        XCTAssertEqual(hours, 72, accuracy: 1)
    }

    func testPatternCoverageTracksAllTrainedPatterns() throws {
        let ctx = try makeContext()
        let now = testNow
        let squat = try makeStrengthEvent(context: ctx, name: "Back Squat", primaryMuscles: ["quadriceps"],
                                           weight: 100, reps: 5, rpe: 8, date: now.addingTimeInterval(-3600))
        let bench = try makeStrengthEvent(context: ctx, name: "Bench Press", primaryMuscles: ["chest"],
                                           weight: 80, reps: 5, rpe: 8, date: now.addingTimeInterval(-3600))

        let facts = CoachFacts.make(from: [squat, bench], goal: .strength, experience: .intermediate, now: now)
        XCTAssertTrue(facts.weeklyBalance.patternsTrained.contains(.squat))
        XCTAssertTrue(facts.weeklyBalance.patternsTrained.contains(.horizontalPush))
    }

    func testInProgressSetsDontCountAsCompletedDose() throws {
        let ctx = try makeContext()
        let now = testNow
        let completedEvent = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                                    weight: 100, reps: 5, rpe: 8, date: now.addingTimeInterval(-3600))

        let inProgSession = try WorkoutRepository.createSession(date: now.addingTimeInterval(-300), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(
            named: "InProg Bench", primaryMuscles: ["chest"], in: ctx)
        _ = try WorkoutRepository.addSet(to: inProgSession, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        let inProgEvent = TrainingEvent.from(session: inProgSession)!

        let facts = CoachFacts.make(from: [completedEvent, inProgEvent], goal: .strength,
                                     experience: .intermediate, now: now)
        XCTAssertEqual(facts.rolling7dCompletedEvents.count, 1)
        XCTAssertEqual(facts.weeklyBalance.strengthDays, 1)
    }

    func testConsecutiveHardDaysTracking() throws {
        let ctx = try makeContext()
        let now = testNow
        var events: [TrainingEvent] = []
        for daysAgo in 1...3 {
            let date = now.addingTimeInterval(-Double(daysAgo) * 86400)
            let session = try WorkoutRepository.createSession(date: date.addingTimeInterval(-600), in: ctx)
            let squat = try WorkoutRepository.findOrCreateExercise(
                named: "Consec Squat \(daysAgo)", primaryMuscles: ["quadriceps"], in: ctx)
            for _ in 0..<8 {
                _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 9, in: ctx)
            }
            session.endedAt = date
            events.append(TrainingEvent.from(session: session)!)
        }

        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)
        XCTAssertGreaterThanOrEqual(facts.weeklyBalance.consecutiveHardDays, 3)
    }

    // MARK: - Phase 2: multi-system facts

    func testSystemExposuresClassifyStrengthByRepBand() throws {
        let ctx = try makeContext()
        let now = testNow
        let heavy = try makeStrengthEvent(context: ctx, name: "Heavy Squat", primaryMuscles: ["quadriceps"],
                                          weight: 140, reps: 3, rpe: 8, date: now.addingTimeInterval(-86400))
        let hyper = try makeStrengthEvent(context: ctx, name: "Curl", primaryMuscles: ["biceps"],
                                          weight: 20, reps: 10, rpe: 8, date: now.addingTimeInterval(-86400))
        let endur = try makeStrengthEvent(context: ctx, name: "Air Squat", primaryMuscles: ["quadriceps"],
                                          weight: 5, reps: 25, rpe: 8, date: now.addingTimeInterval(-86400))
        XCTAssertEqual(heavy.systemExposures.first?.system, .maximalStrength)
        XCTAssertEqual(hyper.systemExposures.first?.system, .hypertrophy)
        XCTAssertEqual(endur.systemExposures.first?.system, .strengthEndurance)
    }

    func testAerobicVigorousIsThresholdAndIntervalIsVO2() {
        let ctx = try! makeContext()
        let now = testNow
        let tempo = makeCardioEvent(context: ctx, type: .run, start: now.addingTimeInterval(-86400),
                                    duration: 1800, avgHR: 165)   // ~0.87 → vigorous continuous
        let hiit = makeCardioEvent(context: ctx, type: .hiit, start: now.addingTimeInterval(-86400),
                                   duration: 1800, avgHR: 170)    // vigorous intervals
        XCTAssertEqual(tempo.systemExposures.first?.system, .threshold)
        XCTAssertEqual(hiit.systemExposures.first?.system, .vo2max)
    }

    func testEasyWalkCountsRecoveryAndBaseNotThreshold() {
        let ctx = try! makeContext()
        let now = testNow
        let walk = makeCardioEvent(context: ctx, type: .walk, start: now.addingTimeInterval(-86400),
                                   duration: 1800, avgHR: 95)     // easy
        let systems = Set(walk.systemExposures.map(\.system))
        XCTAssertTrue(systems.contains(.recovery))
        XCTAssertTrue(systems.contains(.aerobicBase))
        XCTAssertFalse(systems.contains(.threshold))
        XCTAssertFalse(systems.contains(.vo2max))
    }

    func testSystemLoadsAggregateAndStaleness() throws {
        let ctx = try makeContext()
        let now = testNow
        let squat = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                          weight: 140, reps: 3, rpe: 8, date: now.addingTimeInterval(-2 * 86400))
        let facts = CoachFacts.make(from: [squat], goal: .strength, experience: .intermediate, now: now)

        let maxStr = facts.systemLoads[.maximalStrength]
        XCTAssertNotNil(maxStr)
        XCTAssertGreaterThan(maxStr?.trailing7dExposures ?? 0, 0)
        XCTAssertEqual(maxStr?.daysSinceLastExposure, 2)
        XCTAssertFalse(maxStr?.isStale ?? true)

        // VO2 never trained → stale.
        XCTAssertTrue(facts.systemLoads[.vo2max]?.isStale ?? false)
        XCTAssertTrue(facts.staleSystems.contains(.vo2max))
    }

    func testReadinessSnapshotFromEntryFlagsPoor() {
        let entry = ReadinessEntry(date: Date(), muscleSoreness: 2, fatigueEnergy: 3,
                                   sleepQuality: 4, stressMood: 3, hasPainOrIllnessConcern: false)
        let snap = ReadinessSnapshot.from(entry)
        XCTAssertEqual(snap.soreness, 2)
        XCTAssertEqual(snap.motivation, 3)
        XCTAssertTrue(snap.isPoor)        // soreness ≤ 2
        XCTAssertEqual(snap.confidence, .moderate)
    }

    func testAssessmentCoverageMapsKindsToSystems() {
        let now = testNow
        let e1 = AssessmentSummary(kind: .e1RM, exerciseName: "Squat", latest: 150,
                                   latestDate: now.addingTimeInterval(-5 * 86400), baseline: 140,
                                   baselineDate: now.addingTimeInterval(-40 * 86400), best: 150, count: 2)
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                    assessments: [e1], now: now)
        XCTAssertTrue(facts.assessmentCoverage[.maximalStrength]?.hasBaseline ?? false)
        XCTAssertTrue(facts.assessmentCoverage[.maximalStrength]?.isFresh ?? false)
        XCTAssertFalse(facts.assessmentCoverage[.vo2max]?.hasBaseline ?? true)
    }

    func testZoneSourceAgeEstimatedWhenHRPresentUnknownOtherwise() {
        let ctx = try! makeContext()
        let now = testNow
        let withHR = makeCardioEvent(context: ctx, type: .run, start: now.addingTimeInterval(-86400),
                                     duration: 1800, avgHR: 150)
        let factsHR = CoachFacts.make(from: [withHR], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(factsHR.zoneSource, .ageEstimated)

        let noHR = makeCardioEvent(context: ctx, type: .run, start: now.addingTimeInterval(-86400),
                                    duration: 1800, avgHR: nil)
        let factsNoHR = CoachFacts.make(from: [noHR], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(factsNoHR.zoneSource, .unknown)
    }

    // MARK: - Step summary

    func testMakeWithActivityTrendAddsStepSummary() {
        let activity: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 9000)
        }
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                    activityTrend: activity)
        XCTAssertNotNil(facts.stepSummary)
        XCTAssertEqual(facts.stepSummary?.status, .onTrack)
        XCTAssertEqual(facts.stepSummary?.sevenDayAverageSteps, 9000.0)
    }

    func testMakeWithoutActivityTrendHasNoStepSummary() {
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate)
        XCTAssertNil(facts.stepSummary)
    }

    func testMakeWithActivityTrendPreservesExistingBehavior() {
        let now = testNow
        let facts1 = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let activity: [DayActivity] = [DayActivity(date: now, steps: 5000)]
        let facts2 = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                     now: now, activityTrend: activity)

        XCTAssertEqual(facts1.events.count, facts2.events.count)
        XCTAssertEqual(facts1.weeklyBalance.strengthDays, facts2.weeklyBalance.strengthDays)
        XCTAssertEqual(facts1.weeklyBalance.cardioDays, facts2.weeklyBalance.cardioDays)
        XCTAssertEqual(facts1.weeklyBalance.moderateEquivalentMinutes, facts2.weeklyBalance.moderateEquivalentMinutes)
        XCTAssertEqual(facts1.recovery, facts2.recovery)
        XCTAssertEqual(facts1.goal, facts2.goal)
        XCTAssertEqual(facts1.experience, facts2.experience)
        XCTAssertNotNil(facts2.stepSummary)
        XCTAssertNil(facts1.stepSummary)
    }
}
