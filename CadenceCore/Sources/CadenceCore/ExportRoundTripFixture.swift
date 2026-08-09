import Foundation
import SwiftData

/// A single, comprehensive round-trip fixture that seeds **every** exportable
/// type and subtype into a `ModelContext`, shared by unit + UI tests. It exists
/// so the export/import round-trip is proven lossless for the full matrix of
/// cardio types, HIIT presets, strength structural variations, assessment kinds,
/// and preferences (export-freeze fix §4.1).
///
/// All dates are derived from a single `referenceDate` so seeded data is fully
/// deterministic and coach recommendations can be pinned in tests.
public enum ExportRoundTripFixture {

    /// Seeds the store and returns the `ExportPreferences` blob to pass to
    /// `buildExport`, so a caller can round-trip preferences too.
    @discardableResult
    public static func seed(into context: ModelContext,
                            referenceDate: Date = Date(timeIntervalSince1970: 1_750_000_000)) throws -> ExportPreferences {
        try seedCardio(context, ref: referenceDate)
        try seedHIIT(context, ref: referenceDate)
        try seedStrength(context, ref: referenceDate)
        try seedAssessments(context, ref: referenceDate)
        try context.save()
        return preferences(ref: referenceDate)
    }

    // MARK: Cardio — one of each CardioType

    private static func seedCardio(_ ctx: ModelContext, ref: Date) throws {
        func day(_ n: Int) -> Date { ref.addingTimeInterval(Double(n) * 86_400) }

        // run: HR + GPS route
        let run = CardioWorkout(type: .run, start: day(1), end: day(1).addingTimeInterval(1800),
                                distance: 5000, activeEnergy: 320, avgHeartRate: 150,
                                maxHeartRate: 178, source: .iphone, notes: "tempo")
        ctx.insert(run)
        for i in 0..<10 {
            ctx.insert(HRSample(t: Double(i) * 180, bpm: 140 + Double(i), cardio: run))
            ctx.insert(RouteSample(t: Double(i) * 180, lat: 37.0 + Double(i) * 0.001,
                                   lon: -122.0 - Double(i) * 0.001, elevation: 10 + Double(i), cardio: run))
        }

        // cycle: HR + route
        let cycle = CardioWorkout(type: .cycle, start: day(2), end: day(2).addingTimeInterval(2400),
                                  distance: 15000, activeEnergy: 400, avgHeartRate: 140,
                                  maxHeartRate: 165, source: .iphone)
        ctx.insert(cycle)
        for i in 0..<8 {
            ctx.insert(HRSample(t: Double(i) * 300, bpm: 130 + Double(i), cardio: cycle))
            ctx.insert(RouteSample(t: Double(i) * 300, lat: 40.0 + Double(i) * 0.002,
                                   lon: -74.0 - Double(i) * 0.002, elevation: 5, cardio: cycle))
        }

        // walk: route, no HR
        let walk = CardioWorkout(type: .walk, start: day(3), end: day(3).addingTimeInterval(1800),
                                 distance: 2200, activeEnergy: 140, source: .iphone)
        ctx.insert(walk)
        for i in 0..<5 {
            ctx.insert(RouteSample(t: Double(i) * 360, lat: 51.5 + Double(i) * 0.001,
                                   lon: -0.12, elevation: 20, cardio: walk))
        }

        // swim: HR, no route
        let swim = CardioWorkout(type: .swim, start: day(4), end: day(4).addingTimeInterval(1500),
                                 laps: 40, targetLaps: 40, source: .iphone)
        ctx.insert(swim)
        for i in 0..<5 { ctx.insert(HRSample(t: Double(i) * 300, bpm: 120 + Double(i), cardio: swim)) }

        // rowing: machine source
        let row = CardioWorkout(type: .rowing, start: day(5), end: day(5).addingTimeInterval(1200),
                                distance: 4000, activeEnergy: 260, avgHeartRate: 145, source: .machine)
        ctx.insert(row)

        // boxing: custom interval summary
        let boxing = CardioWorkout(type: .boxing, start: day(6), end: day(6).addingTimeInterval(2640),
                                   avgHeartRate: 155, source: .iphone)
        boxing.intervalSummary = IntervalSummary(protocolName: "Boxing", rounds: 12, workSeconds: 180,
                                                 restSeconds: 60, warmupSeconds: 0, cooldownSeconds: 0,
                                                 completedRounds: 12)
        ctx.insert(boxing)

        // other: custom title
        let other = CardioWorkout(type: .other, start: day(7), end: day(7).addingTimeInterval(3600),
                                  activeEnergy: 200, source: .iphone, customTitle: "Yardwork")
        ctx.insert(other)

        // HealthKit-imported (watch) + a manually-logged one
        let imported = CardioWorkout(type: .run, start: day(8), end: day(8).addingTimeInterval(1800),
                                     distance: 4800, activeEnergy: 300, avgHeartRate: 148,
                                     source: .watch, healthKitWorkoutUUID: UUID(),
                                     importedWorkoutKind: .running)
        ctx.insert(imported)

        let logged = CardioWorkout(type: .cycle, start: day(9), end: day(9).addingTimeInterval(1800),
                                   distance: 10000, source: .iphone, isLogged: true)
        ctx.insert(logged)
    }

    // MARK: HIIT — one per interval preset

    private static func seedHIIT(_ ctx: ModelContext, ref: Date) throws {
        func day(_ n: Int) -> Date { ref.addingTimeInterval(Double(n) * 86_400) }
        let presets: [(String, IntervalSummary)] = [
            ("Tabata", IntervalSummary(protocolName: "Tabata", rounds: 8, workSeconds: 20, restSeconds: 10, warmupSeconds: 300, cooldownSeconds: 300, completedRounds: 8)),
            ("Norwegian 4×4", IntervalSummary(protocolName: "Norwegian 4×4", rounds: 4, workSeconds: 240, restSeconds: 180, warmupSeconds: 600, cooldownSeconds: 300, completedRounds: 4)),
            ("Gibala", IntervalSummary(protocolName: "Gibala", rounds: 8, workSeconds: 60, restSeconds: 60, warmupSeconds: 180, cooldownSeconds: 180, completedRounds: 8)),
            ("SIT (Wingate)", IntervalSummary(protocolName: "SIT (Wingate)", rounds: 4, workSeconds: 30, restSeconds: 240, warmupSeconds: 300, cooldownSeconds: 300, completedRounds: 4)),
            ("10-20-30", IntervalSummary(protocolName: "10-20-30", rounds: 15, workSeconds: 30, restSeconds: 20, warmupSeconds: 180, cooldownSeconds: 180, completedRounds: 15)),
            ("REHIT", IntervalSummary(protocolName: "REHIT", rounds: 2, workSeconds: 20, restSeconds: 180, warmupSeconds: 120, cooldownSeconds: 120, completedRounds: 2)),
            ("Custom", IntervalSummary(protocolName: "Custom", rounds: 6, workSeconds: 45, restSeconds: 75, warmupSeconds: 240, cooldownSeconds: 200, completedRounds: 5)),
        ]
        for (i, (name, summary)) in presets.enumerated() {
            let c = CardioWorkout(type: .hiit, start: day(20 + i),
                                  end: day(20 + i).addingTimeInterval(600),
                                  avgHeartRate: 160, source: .iphone, customTitle: name)
            c.intervalSummary = summary
            ctx.insert(c)
        }
    }

    // MARK: Strength — structural variations

    private static func seedStrength(_ ctx: ModelContext, ref: Date) throws {
        func day(_ n: Int) -> Date { ref.addingTimeInterval(Double(n) * 86_400) }

        // 1. one exercise, one set (minimal)
        let s1 = try WorkoutRepository.createSession(title: "Minimal", date: day(40), in: ctx)
        let curl = try WorkoutRepository.findOrCreateExercise(named: "Bicep Curl", in: ctx)
        _ = try WorkoutRepository.addSet(to: s1, exercise: curl, weightKg: 20, reps: 10, completedAt: day(40), in: ctx)

        // 2. multiple exercises × multiple sets
        let s2 = try WorkoutRepository.createSession(title: "Full Body", date: day(41), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", category: .legs, in: ctx)
        for _ in 0..<3 { _ = try WorkoutRepository.addSet(to: s2, exercise: bench, weightKg: 80, reps: 8, completedAt: day(41), in: ctx) }
        for _ in 0..<3 { _ = try WorkoutRepository.addSet(to: s2, exercise: squat, weightKg: 120, reps: 5, completedAt: day(41), in: ctx) }

        // 3. warm-up sets mixed with working sets
        let s3 = try WorkoutRepository.createSession(title: "Warmups", date: day(42), in: ctx)
        _ = try WorkoutRepository.addSet(to: s3, exercise: bench, weightKg: 40, reps: 8, isWarmup: true, completedAt: day(42), in: ctx)
        _ = try WorkoutRepository.addSet(to: s3, exercise: bench, weightKg: 60, reps: 5, isWarmup: true, completedAt: day(42), in: ctx)
        _ = try WorkoutRepository.addSet(to: s3, exercise: bench, weightKg: 90, reps: 5, completedAt: day(42), in: ctx)

        // 4. RPE + per-set notes; session notes
        let s4 = try WorkoutRepository.createSession(title: "RPE Day", date: day(43), in: ctx)
        s4.notes = "Felt strong"
        _ = try WorkoutRepository.addSet(to: s4, exercise: squat, weightKg: 130, reps: 3, rpe: 9, note: "grinder", completedAt: day(43), in: ctx)

        // 5. partner session
        let sam = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let s5 = try WorkoutRepository.createSession(title: "Partner", date: day(44),
                                                     partnerIDs: [sam.id.uuidString], in: ctx)
        _ = try WorkoutRepository.addSet(to: s5, exercise: bench, weightKg: 100, reps: 5, completedAt: day(44), in: ctx)
        _ = try WorkoutRepository.addSet(to: s5, exercise: bench, weightKg: 90, reps: 5, completedAt: day(44), performedBy: sam, in: ctx)

        // 6. bodyweight sets
        let s6 = try WorkoutRepository.createSession(title: "Calisthenics", date: day(45), in: ctx)
        let pullup = try WorkoutRepository.findOrCreateExercise(named: "Pull-Up", in: ctx)
        _ = try WorkoutRepository.addSet(to: s6, exercise: pullup, weightKg: 0, reps: 12, usesBodyweight: true, completedAt: day(45), in: ctx)

        // 7. load-accounting variants (barbell w/ bar weight, dumbbell multiplier)
        let s7 = try WorkoutRepository.createSession(title: "Accounting", date: day(46), in: ctx)
        let barSet = SetEntry(weight: 100, reps: 5, order: 0, completedAt: day(46), session: s7, exercise: squat,
                              barWeightKg: 20, loadMultiplier: 1.0, loadAccountingMode: LoadAccountingMode.barbell.rawValue)
        ctx.insert(barSet)
        let dbSet = SetEntry(weight: 30, reps: 10, order: 1, completedAt: day(46), session: s7, exercise: curl,
                             barWeightKg: 0, loadMultiplier: 1.0, loadAccountingMode: LoadAccountingMode.dualDumbbell.rawValue)
        ctx.insert(dbSet)

        // 8. plan-based session
        let s8 = try WorkoutRepository.createSession(title: "5/3/1 Squat", date: day(47), in: ctx)
        s8.planKey = "preset-531"
        s8.templateName = "5/3/1 Squat"
        s8.plannedExerciseNames = ["Back Squat", "Romanian Deadlift"]
        s8.plannedRepLadder = [5, 3, 1]
        s8.warmupSeconds = 300
        s8.cooldownSeconds = 300
        s8.prescribedLoadKg = 142.5
        s8.endedAt = day(47).addingTimeInterval(3600)
        _ = try WorkoutRepository.addSet(to: s8, exercise: squat, weightKg: 142.5, reps: 5, completedAt: day(47), in: ctx)
    }

    // MARK: Assessments — one of each kind

    private static func seedAssessments(_ ctx: ModelContext, ref: Date) throws {
        func day(_ n: Int) -> Date { ref.addingTimeInterval(Double(n) * 86_400) }
        for (i, kind) in AssessmentKind.allCases.enumerated() {
            ctx.insert(Assessment(date: day(60 + i), kind: kind, value: Double(50 + i),
                                  inputWeight: 100, inputReps: 5,
                                  exerciseName: kind.concernsLift ? "Bench Press" : nil,
                                  protocolName: "protocol-\(kind.rawValue)", notes: "note \(i)",
                                  inputDistance: 1500, inputTime: 480, inputEndingHR: 150,
                                  inputAge: 30, inputSex: 1))
        }
    }

    // MARK: Preferences

    public static func preferences(ref: Date) -> ExportPreferences {
        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .cycle, score: 4, updatedAt: ref),
            AerobicPreference(intent: .vigorousIntervals, modality: .run, score: 2, updatedAt: ref),
        ]
        profile.strengthPreferences = [
            StrengthPreference(pattern: .horizontalPush, exerciseName: "Bench Press", score: 3, updatedAt: ref),
        ]
        profile.avoidedTags = ["boring", "burpees"]

        return ExportPreferences(
            unit: "pounds", prRule: "heaviestSet", oneRepMaxFormula: "brzycki",
            stepGoal: 12_000, weeklyCardioMinutesGoal: 200, restSeconds: 120,
            warmupMinutes: 5, cooldownMinutes: 5, autoStartRest: true, idleTimeoutMinutes: 3,
            gpsHighAccuracy: true, autoPause: true, intervalColorBlind: false, spokenCues: true,
            plateRounding: true, autoSaveHealth: false, autoEndOnIdle: true, workoutSounds: true,
            preWorkoutCountdown: 5, trainingGoal: "strength", experienceLevel: "advanced",
            useHRMonitoring: true, recoveryAwareCoachV2: true,
            favoriteRoutineIDs: ["preset-531", "preset-5x5"], hasCompletedOnboarding: true,
            schedulePreferences: CoachSchedulePreferences(strengthDaysPerWeek: 4, cardioDaysPerWeek: 2,
                                                          allowsTwoADays: true),
            coachProfile: profile)
    }
}
