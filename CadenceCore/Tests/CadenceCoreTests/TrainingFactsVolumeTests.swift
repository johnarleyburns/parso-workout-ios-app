#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

/// Weekly volume after the DB++ adoption: every tally goes through `VolumeCredit`,
/// so a movement credits only the muscles it actually trains, and only if it is
/// volume-eligible at all (decision D3).
struct TrainingFactsVolumeTests {

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

    @Test func specializedCatalogGroupsReceiveWeeklyDirectAndIndirectCredit() throws {
        let context = try makeContext()
        let sessions = try [
            log("Standing Toe Raise", sets: 2, in: context),
            log("Seated Hip Flexion", sets: 2, in: context),
            log("Resisted Neck Rotation Isometric", sets: 2, in: context),
            log("Side-Lying Dumbbell Internal Rotation", sets: 2, in: context),
            log("Sit-Up", sets: 2, in: context),
            log("Dumbbell Scaption", sets: 2, in: context),
        ]
        let weekly = facts(sessions).weeklySetsByGroup
        #expect(weekly[.tibialis] == 2)
        #expect(weekly[.neck] == 2)
        #expect(weekly[.hipFlexors] == 3)
        #expect(weekly[.rotatorCuff] == 3)
    }

    /// The headline change: a deadlift's lower back stabilises. It used to earn
    /// half a set every time and read as trained back volume.
    @Test func deadliftDoesNotCreditLowerBack() throws {
        let ctx = try makeContext()
        let session = try log("Deadlift", sets: 4, in: ctx)
        let f = facts([session])

        #expect(abs((f.weeklySetsByGroup[.glutes] ?? 0) - 4) <= 0.001)
        #expect(abs((f.weeklySetsByGroup[.hamstrings] ?? 0) - 4) <= 0.001)
        #expect(abs((f.weeklySetsByGroup[.quadriceps] ?? 0) - 2) <= 0.001)
        #expect(f.weeklySetsByGroup[.lowerBack] == nil)
        #expect(f.weeklySetsByGroup[.traps] == nil, "the traps hold the bar; they are not trained by it")
    }

    @Test func benchPressCreditsChestFullAndTricepsHalf() throws {
        let ctx = try makeContext()
        let session = try log("Bench Press", sets: 4, in: ctx)
        let f = facts([session])

        #expect(abs((f.weeklySetsByGroup[.chest] ?? 0) - 4) <= 0.001)
        #expect(abs((f.weeklySetsByGroup[.triceps] ?? 0) - 2) <= 0.001)
        #expect(abs((f.weeklySetsByGroup[.shoulders] ?? 0) - 2) <= 0.001)
    }

    /// Stretching, plyometrics and cardio stop inflating the weekly set count.
    @Test func nonVolumeMovementsDoNotCountTowardWeeklyVolume() throws {
        let ctx = try makeContext()
        let stretchName = try #require(try WorkoutRepository.allExercises(ctx)
            .first { $0.trainingTypes.contains(.stretching) }?.name)
        let session = try log(stretchName, sets: 5, in: ctx)
        let f = facts([session])

        #expect(f.weeklySetsByGroup.isEmpty,
                      "\(stretchName) credited \(f.weeklySetsByGroup)")
        #expect(f.weeklySetsByGroup.isEmpty)
        #expect(f.totalWorkingSets == 5, "the sets are still logged, they just do not count as volume")
    }

    @Test func frequencyByGroupCountsDistinctDays() throws {
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
        #expect(f.frequencyByGroup[.chest] == 2)
    }

    /// The body-part rollup credits a part once per set at its best member credit,
    /// which is exactly the primary/secondary semantics it had before.
    @Test func muscleGroupRollupCreditsOncePerSet() throws {
        let ctx = try makeContext()
        // A squat trains quadriceps and glutes directly and the adductors
        // indirectly — three leg groups from one set, but one set of `legs`.
        let session = try log("Back Squat", sets: 3, in: ctx)
        let f = facts([session])

        #expect(abs((f.weeklySetsByGroup[.quadriceps] ?? 0) - 3) <= 0.001)
        #expect(abs((f.weeklySetsByGroup[.glutes] ?? 0) - 3) <= 0.001)
        #expect(abs((f.weeklySetsByGroup[.adductors] ?? 0) - 1.5) <= 0.001)
        #expect(abs((f.weeklySetsByGroup[.quadriceps] ?? 0) - 3) <= 0.001,
                       "three leg groups from one set is still one set of legs")
    }

    @Test func weeklySetsByMuscleMirrorsTheGroupTally() throws {
        let ctx = try makeContext()
        let session = try log("Bench Press", sets: 2, in: ctx)
        let f = facts([session])

        #expect(abs((f.weeklySetsByMuscle["chest"] ?? 0) - 2) <= 0.001)
        #expect(f.weeklySetsByMuscle.count == f.weeklySetsByGroup.count)
        for (group, sets) in f.weeklySetsByGroup {
            #expect(abs((f.weeklySetsByMuscle[group.rawValue] ?? 0) - sets) <= 0.001)
        }
    }

    @Test func volumeTrendByGroupComparesAgainstThePriorWeek() throws {
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
        #expect(f.volumeTrendByGroup[.chest] == .rising)
        #expect(f.volumeTrendByGroup[.chest] == .rising)
    }

    @Test func emptyHistoryTalliesNothing() {
        let f = facts([])
        #expect(f.weeklySetsByGroup.isEmpty)
        #expect(f.frequencyByGroup.isEmpty)
        #expect(f.volumeTrendByGroup.isEmpty)
    }
}

/// The preference that decides which groups the coach programs toward.
struct TrackedMuscleGroupPreferenceTests {

    @Test func defaultMatchesDBPlusPlusTrackedGroups() {
        #expect(CoachSchedulePreferences.default.trackedMuscleGroups ==
                       MuscleGroup.defaultTracked)
    }

    @Test func emptySelectionFallsBackToTheDefault() {
        let prefs = CoachSchedulePreferences(trackedMuscleGroups: [])
        #expect(prefs.trackedMuscleGroups == MuscleGroup.defaultTracked)
    }

    @Test func roundTripsThroughCodable() throws {
        var prefs = CoachSchedulePreferences.default
        prefs.trackedMuscleGroups = [.chest, .lats, .adductors]
        let decoded = try JSONDecoder().decode(
            CoachSchedulePreferences.self, from: try JSONEncoder().encode(prefs))
        #expect(decoded.trackedMuscleGroups == [.chest, .lats, .adductors])
    }

    /// A user who opted a body part out of coverage before the DB++ adoption keeps
    /// that opt-out: every group belonging to it drops out of the tracked set.
    @Test func legacyCoverageOptOutsMigrate() throws {
        let legacyJSON = """
        {"strengthDaysPerWeek":3,"cardioDaysPerWeek":2,"allowsTwoADays":false,
         "dailyStepTarget":8000,"excludedCoverageParts":["calves","abs"],
         "desiredSetsPerExercise":3}
        """
        let decoded = try JSONDecoder().decode(
            CoachSchedulePreferences.self, from: Data(legacyJSON.utf8))

        #expect(!decoded.trackedMuscleGroups.contains(.calves))
        #expect(!decoded.trackedMuscleGroups.contains(.abdominals))
        #expect(decoded.trackedMuscleGroups.contains(.chest))
        #expect(decoded.trackedMuscleGroups.count == MuscleGroup.defaultTracked.count - 3)
    }

    @Test func aFileWithNeitherKeyGetsTheDefault() throws {
        let json = """
        {"strengthDaysPerWeek":3,"cardioDaysPerWeek":2,"allowsTwoADays":false,
         "dailyStepTarget":8000,"desiredSetsPerExercise":3}
        """
        let decoded = try JSONDecoder().decode(
            CoachSchedulePreferences.self, from: Data(json.utf8))
        #expect(decoded.trackedMuscleGroups == MuscleGroup.defaultTracked)
    }
}
#endif
