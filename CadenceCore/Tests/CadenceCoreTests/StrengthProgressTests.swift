import XCTest
import SwiftData
@testable import CadenceCore

/// Tests for the StrengthProgress engine — per-lift estimated-1RM time series
/// bucketed by ISO week.
final class StrengthProgressTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    // MARK: - E1RMSeries trend

    func testTrendEmptySeries() {
        let series = E1RMSeries(exercise: "Squat", points: [])
        XCTAssertEqual(series.trend, .flat)
        XCTAssertEqual(series.current, 0)
        XCTAssertEqual(series.baseline, 0)
        XCTAssertEqual(series.delta, 0)
    }

    func testTrendSinglePoint() {
        let point = E1RMPoint(weekStart: Date(), e1rm: 100)
        let series = E1RMSeries(exercise: "Squat", points: [point])
        XCTAssertEqual(series.trend, .flat)
        XCTAssertEqual(series.current, 100)
        XCTAssertEqual(series.baseline, 100)
        XCTAssertEqual(series.delta, 0)
    }

    func testTrendFlatWithinNoiseBand() {
        let start = Date()
        let series = E1RMSeries(exercise: "Squat", points: [
            E1RMPoint(weekStart: start, e1rm: 100),
            E1RMPoint(weekStart: start.addingTimeInterval(7 * 86400), e1rm: 101.5) // +1.5% < 2%
        ])
        XCTAssertEqual(series.trend, .flat)
    }

    func testTrendRisingAboveNoise() {
        let start = Date()
        let series = E1RMSeries(exercise: "Squat", points: [
            E1RMPoint(weekStart: start, e1rm: 100),
            E1RMPoint(weekStart: start.addingTimeInterval(7 * 86400), e1rm: 105) // +5% > 2%
        ])
        XCTAssertEqual(series.trend, .rising)
    }

    func testTrendDecliningBelowNoise() {
        let start = Date()
        let series = E1RMSeries(exercise: "Squat", points: [
            E1RMPoint(weekStart: start, e1rm: 100),
            E1RMPoint(weekStart: start.addingTimeInterval(7 * 86400), e1rm: 94) // -6% > 2%
        ])
        XCTAssertEqual(series.trend, .declining)
    }

    func testDeltaComputedCorrectly() {
        let start = Date()
        let series = E1RMSeries(exercise: "Bench", points: [
            E1RMPoint(weekStart: start, e1rm: 80),
            E1RMPoint(weekStart: start.addingTimeInterval(14 * 86400), e1rm: 92)
        ])
        XCTAssertEqual(series.delta, 12)
    }

    // MARK: - StrengthProgress.series

    func testSeriesEmptyStoreReturnsEmpty() throws {
        let result = StrengthProgress.series(from: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testSeriesOneLiftTwoWeeksRising() throws {
        let ctx = try makeContext()
        let now = Date()
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "Test Squat", primaryMuscles: ["quads"], in: ctx)

        // Two sessions in different ISO weeks.
        let twoWeeksAgo = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-14 * 86400), in: ctx)
        _ = try WorkoutRepository.addSet(to: twoWeeksAgo, exercise: squat, weightKg: 100, reps: 5, in: ctx)

        let thisWeek = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-1 * 86400), in: ctx)
        _ = try WorkoutRepository.addSet(to: thisWeek, exercise: squat, weightKg: 110, reps: 5, in: ctx)

        let series = StrengthProgress.series(from: [twoWeeksAgo, thisWeek], now: now)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].exercise, "Test Squat")
        XCTAssertEqual(series[0].points.count, 2)
        // Epley: 100*(1+5/30)=116.67 and 110*(1+5/30)=128.33
        XCTAssertGreaterThan(series[0].current, series[0].baseline)
        XCTAssertEqual(series[0].trend, .rising)
    }

    func testSeriesWithinTwoPercentIsFlat() throws {
        let ctx = try makeContext()
        let now = Date()
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: "Test OHP", primaryMuscles: ["delts"], in: ctx)

        // Two sessions in different ISO weeks, same weight → flat trend.
        let twoWeeksAgo = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-14 * 86400), in: ctx)
        _ = try WorkoutRepository.addSet(to: twoWeeksAgo, exercise: ex, weightKg: 60, reps: 5, in: ctx)

        let thisWeek = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-1 * 86400), in: ctx)
        _ = try WorkoutRepository.addSet(to: thisWeek, exercise: ex, weightKg: 60, reps: 5, in: ctx)

        let series = StrengthProgress.series(from: [twoWeeksAgo, thisWeek], now: now)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].trend, .flat)
    }

    func testSeriesTopNSelectsMostSets() throws {
        let ctx = try makeContext()
        let now = Date()
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "Test Squat", primaryMuscles: ["quads"], in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(
            named: "Test Bench", primaryMuscles: ["chest"], in: ctx)
        let curl = try WorkoutRepository.findOrCreateExercise(
            named: "Test Curl", primaryMuscles: ["biceps"], in: ctx)

        let s = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-1 * 86400), in: ctx)
        for _ in 0..<5 { _ = try WorkoutRepository.addSet(to: s, exercise: squat, weightKg: 100, reps: 5, in: ctx) }
        for _ in 0..<3 { _ = try WorkoutRepository.addSet(to: s, exercise: bench, weightKg: 80, reps: 8, in: ctx) }
        for _ in 0..<1 { _ = try WorkoutRepository.addSet(to: s, exercise: curl, weightKg: 30, reps: 10, in: ctx) }

        // topN=2 should return only Squat and Bench
        let series = StrengthProgress.series(from: [s], now: now, topN: 2)
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].exercise, "Test Squat") // most sets
        XCTAssertEqual(series[1].exercise, "Test Bench")
    }

    func testSeriesSessionsOutsideWindowExcluded() throws {
        let ctx = try makeContext()
        let now = Date()
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: "Test Dead", primaryMuscles: ["hamstrings"], in: ctx)

        let old = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-100 * 86400), in: ctx)
        _ = try WorkoutRepository.addSet(to: old, exercise: ex, weightKg: 150, reps: 3, in: ctx)

        let result = StrengthProgress.series(from: [old], now: now, weeks: 12)
        XCTAssertTrue(result.isEmpty)
    }

    func testSeriesDeletedSessionsExcluded() throws {
        let ctx = try makeContext()
        let now = Date()
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: "Test Press", primaryMuscles: ["chest"], in: ctx)

        let s = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-1 * 86400), in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 80, reps: 8, in: ctx)
        try WorkoutRepository.softDeleteSession(s, in: ctx)

        let result = StrengthProgress.series(from: [s], now: now)
        XCTAssertTrue(result.isEmpty)
    }

    func testSeriesWarmupSetsExcluded() throws {
        let ctx = try makeContext()
        let now = Date()
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: "Test Row", primaryMuscles: ["lats"], in: ctx)

        let s = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-1 * 86400), in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 40, reps: 10, isWarmup: true, in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 80, reps: 8, in: ctx)

        let series = StrengthProgress.series(from: [s], now: now)
        XCTAssertEqual(series.count, 1)
        // warmup set of 40kg×10 was excluded, only working set counts
        let epley = WorkoutMath.estimated1RM(weight: 80, reps: 8, formula: .epley)
        XCTAssertEqual(series[0].current, epley, accuracy: 0.01)
    }

    func testSeriesSortedByCurrentDescending() throws {
        let ctx = try makeContext()
        let now = Date()
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "Test Squat", primaryMuscles: ["quads"], in: ctx)
        let curl = try WorkoutRepository.findOrCreateExercise(
            named: "Test Curl", primaryMuscles: ["biceps"], in: ctx)

        let s = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-1 * 86400), in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: squat, weightKg: 120, reps: 3, in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: curl, weightKg: 30, reps: 10, in: ctx)

        let series = StrengthProgress.series(from: [s], now: now, topN: 3)
        XCTAssertEqual(series.count, 2)
        // Squat e1RM (132) > Curl e1RM (40), so Squat first
        XCTAssertEqual(series[0].exercise, "Test Squat")
    }

    func testChartDataIncludesFixedLiftsAndTotal() {
        let now = Date()
        let input = StrengthProgressSessionInput(
            date: now.addingTimeInterval(-86_400),
            deleted: false,
            sets: [
                StrengthProgressSetInput(exerciseName: "Bench Press", completedAt: now,
                                         weightKg: 100, reps: 1, isWarmup: false, isOwnerSet: true),
                StrengthProgressSetInput(exerciseName: "Deadlift", completedAt: now,
                                         weightKg: 150, reps: 1, isWarmup: false, isOwnerSet: true),
                StrengthProgressSetInput(exerciseName: "Back Squat", completedAt: now,
                                         weightKg: 120, reps: 1, isWarmup: false, isOwnerSet: true)
            ])

        let data = StrengthProgress.chartData(from: [input], now: now)

        XCTAssertEqual(data.exerciseNames, ["Bench Press", "Barbell Squat", "Deadlift", "Total"])
        XCTAssertFalse(data.exerciseNames.contains("Powerlifter"))
        XCTAssertEqual(data.allSeries.last?.exercise, "Total")
        XCTAssertEqual(data.allSeries.last?.current ?? 0, 370, accuracy: 0.001)
    }

    func testChartDataTotalIsTheSumOfCanonicalLiftValues() {
        let now = Date()
        let input = StrengthProgressSessionInput(
            date: now.addingTimeInterval(-86_400),
            deleted: false,
            sets: [
                StrengthProgressSetInput(exerciseName: "Barbell Bench Press", completedAt: now,
                                         weightKg: 100, reps: 1, isWarmup: false, isOwnerSet: true),
                StrengthProgressSetInput(exerciseName: "Squat", completedAt: now,
                                         weightKg: 140, reps: 1, isWarmup: false, isOwnerSet: true),
                StrengthProgressSetInput(exerciseName: "Deadlift", completedAt: now,
                                         weightKg: 180, reps: 1, isWarmup: false, isOwnerSet: true)
            ])

        let data = StrengthProgress.chartData(from: [input], now: now)
        let values = Dictionary(uniqueKeysWithValues: data.allSeries.map { ($0.exercise, $0.current) })
        let expectedTotal = (values["Bench Press"] ?? 0)
            + (values["Barbell Squat"] ?? 0)
            + (values["Deadlift"] ?? 0)
        let total = values["Total"] ?? 0

        XCTAssertEqual(total, expectedTotal, accuracy: 0.001)
    }

    func testChartDataTotalCarriesOlderLiftsIntoTheLatestWeek() {
        let calendar = Calendar(identifier: .gregorian)
        let weekOne = Date(timeIntervalSince1970: 1_700_000_000)
        let weekTwo = calendar.date(byAdding: .day, value: 7, to: weekOne)!
        let input = StrengthProgressSessionInput(
            date: weekOne,
            deleted: false,
            sets: [
                StrengthProgressSetInput(exerciseName: "Bench Press", completedAt: weekOne,
                                         weightKg: 100, reps: 1, isWarmup: false, isOwnerSet: true),
                StrengthProgressSetInput(exerciseName: "Back Squat", completedAt: weekOne,
                                         weightKg: 120, reps: 1, isWarmup: false, isOwnerSet: true),
                StrengthProgressSetInput(exerciseName: "Deadlift", completedAt: weekTwo,
                                         weightKg: 150, reps: 1, isWarmup: false, isOwnerSet: true)
            ])

        let data = StrengthProgress.chartData(from: [input], now: weekTwo,
                                              calendar: calendar)
        let total = data.allSeries.first { $0.exercise == "Total" }
        XCTAssertEqual(total?.points.last?.e1rm ?? 0, 370, accuracy: 0.001)
    }

    func testChartDataTotalIncludesCustomChartedLifts() {
        let now = Date()
        let input = StrengthProgressSessionInput(
            date: now.addingTimeInterval(-86_400),
            deleted: false,
            sets: [
                StrengthProgressSetInput(exerciseName: "Bench Press", completedAt: now,
                                         weightKg: 100, reps: 1, isWarmup: false, isOwnerSet: true),
                StrengthProgressSetInput(exerciseName: "Deadlift", completedAt: now,
                                         weightKg: 150, reps: 1, isWarmup: false, isOwnerSet: true),
                StrengthProgressSetInput(exerciseName: "Hack Squat", completedAt: now,
                                         weightKg: 80, reps: 1, isWarmup: false, isOwnerSet: true)
            ])

        let data = StrengthProgress.chartData(from: [input], now: now)
        let values = Dictionary(uniqueKeysWithValues: data.allSeries.map { ($0.exercise, $0.current) })
        XCTAssertEqual(values["Total"] ?? 0, 330, accuracy: 0.001)
    }

    func testChartDataIncludesNonCanonicalLiftsAsCustomSeries() {
        let now = Date()
        let input = StrengthProgressSessionInput(
            date: now.addingTimeInterval(-86_400),
            deleted: false,
            sets: [
                StrengthProgressSetInput(exerciseName: "Overhead Press", completedAt: now,
                                         weightKg: 60, reps: 5, isWarmup: false, isOwnerSet: true)
            ])

        let data = StrengthProgress.chartData(from: [input], now: now)

        XCTAssertTrue(data.exerciseNames.contains("Overhead Press"))
        XCTAssertEqual(data.exerciseNames.last, "Total")
    }

    /// The chart's Total counts only the lifts the user is charting: an
    /// unselected lift must not contribute to it.
    func testTotalSeriesCountsOnlyTheProvidedChartedLifts() {
        let now = Date()
        let input = StrengthProgressSessionInput(
            date: now.addingTimeInterval(-86_400),
            deleted: false,
            sets: [
                StrengthProgressSetInput(exerciseName: "Bench Press", completedAt: now,
                                         weightKg: 100, reps: 1, isWarmup: false, isOwnerSet: true),
                StrengthProgressSetInput(exerciseName: "Deadlift", completedAt: now,
                                         weightKg: 150, reps: 1, isWarmup: false, isOwnerSet: true)
            ])

        let data = StrengthProgress.chartData(from: [input], now: now)
        let benchOnly = data.allSeries.filter { $0.exercise == "Bench Press" }
        let benchTotal = StrengthProgress.totalSeries(from: benchOnly)
        XCTAssertEqual(benchTotal.exercise, "Total")
        XCTAssertEqual(benchTotal.current, 100, accuracy: 0.001)

        let chartedLifts = data.allSeries.filter { $0.exercise != "Total" }
        XCTAssertEqual(StrengthProgress.totalSeries(from: chartedLifts).current, 250, accuracy: 0.001)
    }

    // MARK: E1RMPoint

    func testE1RMPointIdentifiableByWeekStart() {
        let date = Date()
        let a = E1RMPoint(weekStart: date, e1rm: 100)
        let b = E1RMPoint(weekStart: date, e1rm: 100)
        XCTAssertEqual(a.id, b.id)
    }
}
