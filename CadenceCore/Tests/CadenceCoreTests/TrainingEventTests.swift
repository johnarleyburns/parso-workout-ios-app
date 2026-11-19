#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

struct TrainingEventTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var testNow: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 5; comps.hour = 12; comps.minute = 0; comps.second = 0
        return cal.date(from: comps) ?? Date()
    }

    @Test func strengthSessionToTrainingEvent() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(date: testNow.addingTimeInterval(-3600), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "Back Squat", primaryMuscles: ["quadriceps"], secondaryMuscles: ["glutes"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 8, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 9, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 9, in: ctx)
        session.endedAt = testNow.addingTimeInterval(-3300)
        try ctx.save()

        let event = TrainingEvent.from(session: session)
        #expect(event != nil)
        #expect(event?.source == .appStrength)
        #expect(event?.completion == .completed)

        guard case .strength(let details) = event?.kind, let d = details else {
            Issue.record("Expected strength event")
            return
        }
        #expect(d.exercises.count == 1)
        let ex = d.exercises.first!
        #expect(ex.exerciseName == "Back Squat")
        #expect(ex.hardSetCount == 3)
        #expect(ex.topSetWeightKg == 100)
        #expect(ex.topSetReps == 5)
        #expect(ex.patterns.contains(.squat))
        #expect(ex.muscleGroups.contains(.quadriceps))
        #expect(ex.maxRPE == 9)
        #expect(ex.maxRPE == 9)
    }

    @Test func cardioWorkoutToTrainingEvent() throws {
        let ctx = try makeContext()
        let cardio = CardioWorkout(type: .run, start: testNow.addingTimeInterval(-3600),
                                    end: testNow.addingTimeInterval(-1800), distance: 5000,
                                    avgHeartRate: 160, source: .iphone)
        ctx.insert(cardio)
        try ctx.save()

        let event = TrainingEvent.from(cardio: cardio)
        #expect(event.source == .appCardio)

        guard case .aerobic(let d) = event.kind else {
            Issue.record("Expected aerobic event")
            return
        }
        #expect(d.modality == .running)
        #expect(abs(d.duration - 1800) <= 1)
        #expect(d.intensity == .vigorous)
        #expect(d.intensityConfidence == .moderate)
    }

    @Test func sampledCardioPreservesIntervalDistributionAndWeightedCredit() throws {
        let ctx = try makeContext()
        let start = testNow.addingTimeInterval(-1800)
        let cardio = CardioWorkout(type: .other, start: start,
                                   end: start.addingTimeInterval(1200), source: .iphone)
        ctx.insert(cardio)
        let samples = [
            (0.0, 136.0), (120.0, 161.0), (180.0, 136.0),
            (300.0, 161.0), (360.0, 136.0)
        ]
        for (t, bpm) in samples {
            ctx.insert(HRSample(t: t, bpm: bpm, cardio: cardio))
        }
        try ctx.save()

        let event = TrainingEvent.from(cardio: cardio, userAge: 50)
        guard case .intervals(let details) = event.kind else {
            Issue.record("Repeated high-HR bouts should be classified as interval-like")
            return
        }
        #expect(abs(details.moderateMinutes - 18) <= 0.001)
        #expect(abs(details.vigorousMinutes - 2) <= 0.001)
        #expect(abs(details.moderateEquivalentMinutes - 22) <= 0.001)
        #expect(details.intensityConfidence == .high)
    }

    @Test func cardioWorkoutWithoutHRDefaultsToModerateLowConfidence() throws {
        let ctx = try makeContext()
        let cardio = CardioWorkout(type: .walk, start: testNow.addingTimeInterval(-3600),
                                    end: testNow.addingTimeInterval(-1800), source: .iphone)
        ctx.insert(cardio)
        try ctx.save()

        let event = TrainingEvent.from(cardio: cardio)
        guard case .aerobic(let d) = event.kind else {
            Issue.record("Expected aerobic")
            return
        }
        #expect(d.intensity == .moderate)
        #expect(d.intensityConfidence == .low)
    }

    @Test func inProgressSessionHasInProgressCompletion() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(date: testNow.addingTimeInterval(-600), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "InProg Squat", primaryMuscles: ["quadriceps"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 80, reps: 5, in: ctx)

        let event = TrainingEvent.from(session: session)
        #expect(event?.completion == .inProgress)
    }

    @Test func warmupSetsNotCountedAsHard() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(date: testNow.addingTimeInterval(-3600), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(
            named: "Bench Press", primaryMuscles: ["chest"], secondaryMuscles: ["triceps"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 40, reps: 10, isWarmup: true, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 5, isWarmup: true, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, rpe: 8, in: ctx)
        session.endedAt = testNow

        let event = TrainingEvent.from(session: session)
        guard case .strength(let details) = event?.kind, let d = details else {
            Issue.record()
            return
        }
        #expect(d.exercises.first?.hardSetCount == 1)
        #expect(d.totalHardSets == 1)
    }

    @Test func hardClassification() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(date: testNow.addingTimeInterval(-3600), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "Hard Squat", primaryMuscles: ["quadriceps"], in: ctx)
        for _ in 0..<8 {
            _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 9, in: ctx)
        }
        session.endedAt = testNow

        let event = TrainingEvent.from(session: session)
        #expect(event?.isHard ?? false)
    }

    @Test func easyCardioIsNotHard() throws {
        let ctx = try makeContext()
        let cardio = CardioWorkout(type: .walk, start: testNow.addingTimeInterval(-3600),
                                    end: testNow.addingTimeInterval(-1800), avgHeartRate: 100, source: .iphone)
        ctx.insert(cardio)
        try ctx.save()

        let event = TrainingEvent.from(cardio: cardio)
        #expect(!event.isHard)
    }

    // MARK: - Cardio intensity truth (coach-user-control Phase 1)

    private func intensity(type: CardioType, avgHR: Double? = nil, maxHR: Double? = nil,
                           age: Int? = nil) throws -> AerobicEventDetails.IntensityClassification {
        let ctx = try makeContext()
        let cardio = CardioWorkout(type: type, start: testNow.addingTimeInterval(-3600),
                                   end: testNow.addingTimeInterval(-1800),
                                   avgHeartRate: avgHR, maxHeartRate: maxHR, source: .iphone)
        ctx.insert(cardio)
        try ctx.save()
        let event = TrainingEvent.from(cardio: cardio, userAge: age)
        switch event.kind {
        case .aerobic(let d), .intervals(let d): return d.intensity
        default:
            Issue.record("Expected aerobic/interval event")
            return .easy
        }
    }

    /// The export's real 7/06–7/13 sessions (age 50) must all classify vigorous:
    /// HIIT and boxing are intense by construction, HR or not.
    @Test func exportWeekIntenseSessionsClassifyVigorous() throws {
        // 7/06 boxing, no HR
        #expect(try intensity(type: .boxing, age: 50) == .vigorous)
        // 7/07 HIIT ×3, no HR
        #expect(try intensity(type: .hiit, age: 50) == .vigorous)
        // 7/08 HIIT, avg 116 / peak 146
        #expect(try intensity(type: .hiit, avgHR: 116, maxHR: 146, age: 50) == .vigorous)
        // 7/09 boxing, avg 139 / peak 170
        #expect(try intensity(type: .boxing, avgHR: 139, maxHR: 170, age: 50) == .vigorous)
        // 7/13 boxing, avg 128 / peak 157
        #expect(try intensity(type: .boxing, avgHR: 128, maxHR: 157, age: 50) == .vigorous)
    }

    /// Age matters: 140 bpm average is vigorous for a 50-year-old (Tanaka HRmax
    /// ≈ 173) but only moderate for a 30-year-old (≈ 187).
    @Test func ageAnchoredMaxHRChangesClassification() throws {
        #expect(try intensity(type: .run, avgHR: 140, age: 50) == .vigorous)
        #expect(try intensity(type: .run, avgHR: 140, age: 30) == .moderate)
        // Unknown age falls back to HRmax 190 — same bucket as before the fix.
        #expect(try intensity(type: .run, avgHR: 140) == .moderate)
    }

    /// Peak-anchored: an interval-style session whose peaks hit ≥90% HRmax is
    /// vigorous even when rest intervals drag the average below 80%.
    @Test func peakHRMarksVigorousDespiteLowAverage() throws {
        // Age 50 → HRmax 173; avg 120 (69%) but peak 160 (92%).
        #expect(try intensity(type: .run, avgHR: 120, maxHR: 160, age: 50) == .vigorous)
    }

    /// A genuine easy walk stays easy, and a no-HR walk keeps the moderate default.
    @Test func easyWalkStaysEasy() throws {
        #expect(try intensity(type: .walk, avgHR: 96, maxHR: 104, age: 50) == .easy)
        #expect(try intensity(type: .walk, age: 50) == .moderate)
    }

    /// No-HR HIIT/boxing → vigorous AND hard (feeds hardDoneToday / weekly load).
    @Test func noHRIntenseModalitiesAreHard() throws {
        let ctx = try makeContext()
        let boxing = CardioWorkout(type: .boxing, start: testNow.addingTimeInterval(-3600),
                                   end: testNow.addingTimeInterval(-1800), source: .iphone)
        ctx.insert(boxing)
        try ctx.save()
        let event = TrainingEvent.from(cardio: boxing, userAge: 50)
        #expect(event.isHard)
    }
}
#endif
