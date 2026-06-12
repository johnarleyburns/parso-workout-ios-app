import XCTest
import SwiftData
@testable import CadenceCore

@MainActor
final class WorkoutSummaryDataTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    // MARK: Strength

    func testStrengthSummaryBasics() throws {
        let ctx = try makeContext()
        let start = Date(timeIntervalSince1970: 1000)
        let session = try WorkoutRepository.createSession(title: "Push Day", date: start, in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 105, reps: 3, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 140, reps: 5, in: ctx)
        session.endedAt = start.addingTimeInterval(3600)

        let s = WorkoutSummaryData.from(session: session)

        XCTAssertEqual(s.kind, .strength)
        XCTAssertEqual(s.title, "Push Day")
        XCTAssertEqual(s.date, start)
        XCTAssertEqual(s.durationSec, 3600, accuracy: 0.001)
        // totalVolumeKg = 100*5 + 105*3 + 140*5 = 500 + 315 + 700 = 1515
        XCTAssertEqual(s.totalVolumeKg ?? 0, 1515, accuracy: 0.001)
        XCTAssertEqual(s.setCount, 3)

        // Exercise names/order match exercisesInOrder.
        XCTAssertEqual(s.exercises.map(\.name), ["Bench Press", "Back Squat"])
        let benchLine = try XCTUnwrap(s.exercises.first)
        XCTAssertEqual(benchLine.setCount, 2)
        XCTAssertEqual(benchLine.reps, [5, 3])
        XCTAssertEqual(benchLine.topSetWeightKg ?? 0, 105, accuracy: 0.001)

        // Cardio fields nil/empty on a strength summary.
        XCTAssertNil(s.distanceM)
        XCTAssertNil(s.paceSecPerKm)
        XCTAssertNil(s.calories)
        XCTAssertNil(s.avgHR)
        XCTAssertNil(s.maxHR)
        XCTAssertTrue(s.hr.isEmpty)
        XCTAssertTrue(s.route.isEmpty)
    }

    func testStrengthSummaryExcludesPartnerSets() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Bench", date: Date(timeIntervalSince1970: 2000), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)

        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)        // owner
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 10,
                                         performedBy: sam, in: ctx)                                            // partner

        let s = WorkoutSummaryData.from(session: session)
        // Only the owner's set counts toward volume and the exercise line.
        XCTAssertEqual(s.totalVolumeKg ?? 0, 500, accuracy: 0.001)
        XCTAssertEqual(s.setCount, 1)
        XCTAssertEqual(s.exercises.count, 1)
        XCTAssertEqual(s.exercises.first?.reps, [5])
        XCTAssertEqual(s.exercises.first?.topSetWeightKg ?? 0, 100, accuracy: 0.001)
    }

    func testStrengthSummaryExcludesWarmupSets() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Squat", date: Date(timeIntervalSince1970: 3000), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 60, reps: 8, isWarmup: true, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 140, reps: 5, in: ctx)

        let s = WorkoutSummaryData.from(session: session)
        // Warmup excluded from volume, setCount, reps, and top set.
        XCTAssertEqual(s.totalVolumeKg ?? 0, 700, accuracy: 0.001)
        XCTAssertEqual(s.setCount, 1)
        XCTAssertEqual(s.exercises.first?.reps, [5])
        XCTAssertEqual(s.exercises.first?.topSetWeightKg ?? 0, 140, accuracy: 0.001)
    }

    // MARK: Cardio

    func testCardioSummaryPopulatesMetrics() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let end = start.addingTimeInterval(600)   // 10 minutes
        let c = CardioWorkout(type: .walk, start: start, end: end,
                              distance: 2000, activeEnergy: 120,
                              avgHeartRate: 110, maxHeartRate: 135)

        let s = WorkoutSummaryData.from(cardio: c)

        XCTAssertEqual(s.kind, .cardio)
        XCTAssertEqual(s.title, "Walk")
        XCTAssertEqual(s.date, start)
        XCTAssertEqual(s.durationSec, 600, accuracy: 0.001)   // end - start
        XCTAssertEqual(s.distanceM ?? 0, 2000, accuracy: 0.001)
        // pace = 600s / 2km = 300 s/km
        XCTAssertEqual(s.paceSecPerKm ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(s.calories ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(s.avgHR ?? 0, 110, accuracy: 0.001)
        XCTAssertEqual(s.maxHR ?? 0, 135, accuracy: 0.001)

        // Strength fields empty/nil on a cardio summary.
        XCTAssertNil(s.totalVolumeKg)
        XCTAssertEqual(s.setCount, 0)
        XCTAssertTrue(s.exercises.isEmpty)
    }

    func testCardioSummaryCarriesHRAndRoute() throws {
        let start = Date(timeIntervalSince1970: 20_000)
        let c = CardioWorkout(type: .run, start: start, end: start.addingTimeInterval(60), distance: 200)
        c.hrSamples = [HRSample(t: 10, bpm: 120, cardio: c), HRSample(t: 0, bpm: 100, cardio: c)]
        c.routeSamples = [RouteSample(t: 5, lat: 1, lon: 2, cardio: c),
                          RouteSample(t: 0, lat: 3, lon: 4, cardio: c)]

        let s = WorkoutSummaryData.from(cardio: c)
        // Ordered by t ascending.
        XCTAssertEqual(s.hr.map(\.t), [0, 10])
        XCTAssertEqual(s.hr.map(\.bpm), [100, 120])
        XCTAssertEqual(s.route.map(\.lat), [3, 1])
        XCTAssertEqual(s.route.map(\.lon), [4, 2])
    }

    func testCardioSummaryNilDistanceHasNilPace() throws {
        let start = Date(timeIntervalSince1970: 30_000)
        let c = CardioWorkout(type: .boxing, start: start, end: start.addingTimeInterval(300))
        let s = WorkoutSummaryData.from(cardio: c)
        XCTAssertNil(s.distanceM)
        XCTAssertNil(s.paceSecPerKm)
    }
}
