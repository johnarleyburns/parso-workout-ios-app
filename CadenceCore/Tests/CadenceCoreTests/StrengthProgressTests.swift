#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

/// Tests for the StrengthProgress engine — per-lift estimated-1RM time series
/// bucketed by ISO week.
struct StrengthProgressTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    // MARK: - E1RMSeries trend

    @Test func trendEmptySeries() {
        let series = E1RMSeries(exercise: "Squat", points: [])
        #expect(series.trend == .flat)
        #expect(series.current == 0)
        #expect(series.baseline == 0)
        #expect(series.delta == 0)
    }

    @Test func trendSinglePoint() {
        let point = E1RMPoint(weekStart: Date(), e1rm: 100)
        let series = E1RMSeries(exercise: "Squat", points: [point])
        #expect(series.trend == .flat)
        #expect(series.current == 100)
        #expect(series.baseline == 100)
        #expect(series.delta == 0)
    }

    @Test func trendFlatWithinNoiseBand() {
        let start = Date()
        let series = E1RMSeries(exercise: "Squat", points: [
            E1RMPoint(weekStart: start, e1rm: 100),
            E1RMPoint(weekStart: start.addingTimeInterval(7 * 86400), e1rm: 101.5) // +1.5% < 2%
        ])
        #expect(series.trend == .flat)
    }

    @Test func trendRisingAboveNoise() {
        let start = Date()
        let series = E1RMSeries(exercise: "Squat", points: [
            E1RMPoint(weekStart: start, e1rm: 100),
            E1RMPoint(weekStart: start.addingTimeInterval(7 * 86400), e1rm: 105) // +5% > 2%
        ])
        #expect(series.trend == .rising)
    }

    @Test func trendDecliningBelowNoise() {
        let start = Date()
        let series = E1RMSeries(exercise: "Squat", points: [
            E1RMPoint(weekStart: start, e1rm: 100),
            E1RMPoint(weekStart: start.addingTimeInterval(7 * 86400), e1rm: 94) // -6% > 2%
        ])
        #expect(series.trend == .declining)
    }

    @Test func deltaComputedCorrectly() {
        let start = Date()
        let series = E1RMSeries(exercise: "Bench", points: [
            E1RMPoint(weekStart: start, e1rm: 80),
            E1RMPoint(weekStart: start.addingTimeInterval(14 * 86400), e1rm: 92)
        ])
        #expect(series.delta == 12)
    }

    // MARK: - StrengthProgress.series

    @Test func seriesEmptyStoreReturnsEmpty() throws {
        let result = StrengthProgress.series(from: [])
        #expect(result.isEmpty)
    }

    @Test func seriesOneLiftTwoWeeksRising() throws {
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
        #expect(series.count == 1)
        #expect(series[0].exercise == "Test Squat")
        #expect(series[0].points.count == 2)
        // Epley: 100*(1+5/30)=116.67 and 110*(1+5/30)=128.33
        #expect(series[0].current > series[0].baseline)
        #expect(series[0].trend == .rising)
    }

    @Test func seriesWithinTwoPercentIsFlat() throws {
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
        #expect(series.count == 1)
        #expect(series[0].trend == .flat)
    }

    @Test func seriesTopNSelectsMostSets() throws {
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
        #expect(series.count == 2)
        #expect(series[0].exercise == "Test Squat") // most sets
        #expect(series[1].exercise == "Test Bench")
    }

    @Test func seriesSessionsOutsideWindowExcluded() throws {
        let ctx = try makeContext()
        let now = Date()
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: "Test Dead", primaryMuscles: ["hamstrings"], in: ctx)

        let old = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-100 * 86400), in: ctx)
        _ = try WorkoutRepository.addSet(to: old, exercise: ex, weightKg: 150, reps: 3, in: ctx)

        let result = StrengthProgress.series(from: [old], now: now, weeks: 12)
        #expect(result.isEmpty)
    }

    @Test func seriesDeletedSessionsExcluded() throws {
        let ctx = try makeContext()
        let now = Date()
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: "Test Press", primaryMuscles: ["chest"], in: ctx)

        let s = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-1 * 86400), in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 80, reps: 8, in: ctx)
        try WorkoutRepository.softDeleteSession(s, in: ctx)

        let result = StrengthProgress.series(from: [s], now: now)
        #expect(result.isEmpty)
    }

    @Test func seriesWarmupSetsExcluded() throws {
        let ctx = try makeContext()
        let now = Date()
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: "Test Row", primaryMuscles: ["lats"], in: ctx)

        let s = try WorkoutRepository.createSession(
            date: now.addingTimeInterval(-1 * 86400), in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 40, reps: 10, isWarmup: true, in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 80, reps: 8, in: ctx)

        let series = StrengthProgress.series(from: [s], now: now)
        #expect(series.count == 1)
        // warmup set of 40kg×10 was excluded, only working set counts
        let epley = WorkoutMath.estimated1RM(weight: 80, reps: 8, formula: .epley)
        #expect(abs(series[0].current - epley) <= 0.01)
    }

    @Test func seriesSortedByCurrentDescending() throws {
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
        #expect(series.count == 2)
        // Squat e1RM (132) > Curl e1RM (40), so Squat first
        #expect(series[0].exercise == "Test Squat")
    }

    @Test func chartDataIncludesFixedLiftsAndTotal() {
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

        #expect(data.exerciseNames == ["Bench Press", "Barbell Squat", "Deadlift", "Total"])
        #expect(!data.exerciseNames.contains("Powerlifter"))
        #expect(data.allSeries.last?.exercise == "Total")
        #expect(abs((data.allSeries.last?.current ?? 0) - 370) <= 0.001)
    }

    @Test func chartDataTotalIsTheSumOfCanonicalLiftValues() {
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

        #expect(abs(total - expectedTotal) <= 0.001)
    }

    @Test func chartDataTotalCarriesOlderLiftsIntoTheLatestWeek() {
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
        #expect(abs((total?.points.last?.e1rm ?? 0) - 370) <= 0.001)
    }

    @Test func chartDataTotalIncludesCustomChartedLifts() {
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
        #expect(abs((values["Total"] ?? 0) - 330) <= 0.001)
    }

    @Test func chartDataIncludesNonCanonicalLiftsAsCustomSeries() {
        let now = Date()
        let input = StrengthProgressSessionInput(
            date: now.addingTimeInterval(-86_400),
            deleted: false,
            sets: [
                StrengthProgressSetInput(exerciseName: "Overhead Press", completedAt: now,
                                         weightKg: 60, reps: 5, isWarmup: false, isOwnerSet: true)
            ])

        let data = StrengthProgress.chartData(from: [input], now: now)

        #expect(data.exerciseNames.contains("Overhead Press"))
        #expect(data.exerciseNames.last == "Total")
    }

    /// The chart's Total counts only the lifts the user is charting: an
    /// unselected lift must not contribute to it.
    @Test func totalSeriesCountsOnlyTheProvidedChartedLifts() {
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
        #expect(benchTotal.exercise == "Total")
        #expect(abs(benchTotal.current - 100) <= 0.001)

        let chartedLifts = data.allSeries.filter { $0.exercise != "Total" }
        #expect(abs(StrengthProgress.totalSeries(from: chartedLifts).current - 250) <= 0.001)
    }

    // MARK: E1RMPoint

    @Test func e1RMPointIdentifiableByWeekStart() {
        let date = Date()
        let a = E1RMPoint(weekStart: date, e1rm: 100)
        let b = E1RMPoint(weekStart: date, e1rm: 100)
        #expect(a.id == b.id)
    }
}
#endif
