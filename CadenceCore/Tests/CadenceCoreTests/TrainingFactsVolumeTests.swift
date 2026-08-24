import XCTest
import SwiftData
@testable import CadenceCore

/// Weekly volume after the DB++ adoption: every tally goes through `VolumeCredit`,
/// so a movement credits only the muscles it actually trains, and only if it is
/// volume-eligible at all (decision D3).
final class TrainingFactsVolumeTests: XCTestCase {

    private let testNow = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Exercise.self, WorkoutSession.self, SetEntry.self, Person.self,
            Assessment.self, CardioWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        return ctx
    }

    private func log(_ name: String, sets: Int, in ctx: ModelContext) throws -> WorkoutSession {
        let session = try WorkoutRepository.createSession(
            date: testNow.addingTimeInterval(-2 * 86_400), in: ctx)
        let exercise = try WorkoutRepository.findOrCreateExercise(named: name, in: ctx)
        for _ in 0..<sets {
            _ = try WorkoutRepository.addSet(to: session, exercise: exercise,
                                             weightKg: 60, reps: 8, in: ctx)
        }
        return session
    }

    private func facts(_ sessions: [WorkoutSession]) -> TrainingFacts {
        TrainingFacts.make(sessions: sessions, now: testNow,
                           goal: .hypertrophy, experience: .intermediate)
    }

    /// The headline change: a deadlift's lower back stabilises. It used to earn
    /// half a set every time and read as trained back volume.
    func testDeadliftDoesNotCreditLowerBack() throws {
        let ctx = try makeContext()
        let session = try log("Deadlift", sets: 4, in: ctx)
        let f = facts([session])

        XCTAssertEqual(f.weeklySetsByGroup[.glutes] ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(f.weeklySetsByGroup[.hamstrings] ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(f.weeklySetsByGroup[.quadriceps] ?? 0, 2, accuracy: 0.001)
        XCTAssertNil(f.weeklySetsByGroup[.lowerBack])
        XCTAssertNil(f.weeklySetsByGroup[.traps], "the traps hold the bar; they are not trained by it")
    }

    func testBenchPressCreditsChestFullAndTricepsHalf() throws {
        let ctx = try makeContext()
        let session = try log("Bench Press", sets: 4, in: ctx)
        let f = facts([session])

        XCTAssertEqual(f.weeklySetsByGroup[.chest] ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(f.weeklySetsByGroup[.triceps] ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(f.weeklySetsByGroup[.shoulders] ?? 0, 2, accuracy: 0.001)
    }

    /// Stretching, plyometrics and cardio stop inflating the weekly set count.
    func testNonVolumeMovementsDoNotCountTowardWeeklyVolume() throws {
        let ctx = try makeContext()
        let stretchName = try XCTUnwrap(try WorkoutRepository.allExercises(ctx)
            .first { $0.trainingTypes.contains(.stretching) }?.name)
        let session = try log(stretchName, sets: 5, in: ctx)
        let f = facts([session])

        XCTAssertTrue(f.weeklySetsByGroup.isEmpty,
                      "\(stretchName) credited \(f.weeklySetsByGroup)")
        XCTAssertTrue(f.weeklySetsByPart.isEmpty)
        XCTAssertEqual(f.totalWorkingSets, 5, "the sets are still logged, they just do not count as volume")
    }

    func testFrequencyByGroupCountsDistinctDays() throws {
        let ctx = try makeContext()
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        var sessions: [WorkoutSession] = []
        for dayOffset in [1, 1, 3] {
            let session = try WorkoutRepository.createSession(
                date: testNow.addingTimeInterval(Double(-dayOffset) * 86_400), in: ctx)
            _ = try WorkoutRepository.addSet(to: session, exercise: bench,
                                             weightKg: 60, reps: 8, in: ctx)
            sessions.append(session)
        }
        let f = facts(sessions)
        XCTAssertEqual(f.frequencyByGroup[.chest], 2)
    }

    /// The body-part rollup credits a part once per set at its best member credit,
    /// which is exactly the primary/secondary semantics it had before.
    func testBodyPartRollupCreditsOncePerSet() throws {
        let ctx = try makeContext()
        // A squat trains quadriceps and glutes directly and the adductors
        // indirectly — three leg groups from one set, but one set of `legs`.
        let session = try log("Back Squat", sets: 3, in: ctx)
        let f = facts([session])

        XCTAssertEqual(f.weeklySetsByGroup[.quadriceps] ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(f.weeklySetsByGroup[.glutes] ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(f.weeklySetsByGroup[.adductors] ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(f.weeklySetsByPart[.legs] ?? 0, 3, accuracy: 0.001,
                       "three leg groups from one set is still one set of legs")
    }

    func testWeeklySetsByMuscleMirrorsTheGroupTally() throws {
        let ctx = try makeContext()
        let session = try log("Bench Press", sets: 2, in: ctx)
        let f = facts([session])

        XCTAssertEqual(f.weeklySetsByMuscle["chest"] ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(f.weeklySetsByMuscle.count, f.weeklySetsByGroup.count)
        for (group, sets) in f.weeklySetsByGroup {
            XCTAssertEqual(f.weeklySetsByMuscle[group.rawValue] ?? 0, sets, accuracy: 0.001)
        }
    }

    func testVolumeTrendByGroupComparesAgainstThePriorWeek() throws {
        let ctx = try makeContext()
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let thisWeek = try WorkoutRepository.createSession(
            date: testNow.addingTimeInterval(-1 * 86_400), in: ctx)
        for _ in 0..<6 {
            _ = try WorkoutRepository.addSet(to: thisWeek, exercise: bench,
                                             weightKg: 60, reps: 8, in: ctx)
        }
        let priorWeek = try WorkoutRepository.createSession(
            date: WeeklyStats.weekStart(now: testNow).addingTimeInterval(-2 * 86_400), in: ctx)
        for _ in 0..<2 {
            _ = try WorkoutRepository.addSet(to: priorWeek, exercise: bench,
                                             weightKg: 60, reps: 8, in: ctx)
        }

        let f = facts([thisWeek, priorWeek])
        XCTAssertEqual(f.volumeTrendByGroup[.chest], .rising)
        XCTAssertEqual(f.volumeTrendByPart[.chest], .rising)
    }

    func testEmptyHistoryTalliesNothing() {
        let f = facts([])
        XCTAssertTrue(f.weeklySetsByGroup.isEmpty)
        XCTAssertTrue(f.frequencyByGroup.isEmpty)
        XCTAssertTrue(f.volumeTrendByGroup.isEmpty)
    }
}

/// The preference that decides which groups the coach programs toward.
final class TrackedMuscleGroupPreferenceTests: XCTestCase {

    func testDefaultIsTheThirteenTrackedGroups() {
        XCTAssertEqual(CoachSchedulePreferences.default.trackedMuscleGroups,
                       MuscleGroup.defaultTracked)
    }

    func testEmptySelectionFallsBackToTheDefault() {
        let prefs = CoachSchedulePreferences(trackedMuscleGroups: [])
        XCTAssertEqual(prefs.trackedMuscleGroups, MuscleGroup.defaultTracked)
    }

    func testRoundTripsThroughCodable() throws {
        var prefs = CoachSchedulePreferences.default
        prefs.trackedMuscleGroups = [.chest, .lats, .adductors]
        let decoded = try JSONDecoder().decode(
            CoachSchedulePreferences.self, from: try JSONEncoder().encode(prefs))
        XCTAssertEqual(decoded.trackedMuscleGroups, [.chest, .lats, .adductors])
    }

    /// A user who opted a body part out of coverage before the DB++ adoption keeps
    /// that opt-out: every group belonging to it drops out of the tracked set.
    func testLegacyCoverageOptOutsMigrate() throws {
        let legacyJSON = """
        {"strengthDaysPerWeek":3,"cardioDaysPerWeek":2,"allowsTwoADays":false,
         "dailyStepTarget":8000,"excludedCoverageParts":["calves","abs"],
         "desiredSetsPerExercise":3}
        """
        let decoded = try JSONDecoder().decode(
            CoachSchedulePreferences.self, from: Data(legacyJSON.utf8))

        XCTAssertFalse(decoded.trackedMuscleGroups.contains(.calves))
        XCTAssertFalse(decoded.trackedMuscleGroups.contains(.abdominals))
        XCTAssertTrue(decoded.trackedMuscleGroups.contains(.chest))
        XCTAssertEqual(decoded.trackedMuscleGroups.count, MuscleGroup.defaultTracked.count - 2)
    }

    func testAFileWithNeitherKeyGetsTheDefault() throws {
        let json = """
        {"strengthDaysPerWeek":3,"cardioDaysPerWeek":2,"allowsTwoADays":false,
         "dailyStepTarget":8000,"desiredSetsPerExercise":3}
        """
        let decoded = try JSONDecoder().decode(
            CoachSchedulePreferences.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.trackedMuscleGroups, MuscleGroup.defaultTracked)
    }
}
