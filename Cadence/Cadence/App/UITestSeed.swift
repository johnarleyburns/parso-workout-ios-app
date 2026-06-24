import Foundation
import SwiftData
import CadenceCore

/// Deterministic data seeding for UI tests, driven by launch arguments. The
/// store is in-memory in UI-test mode, so each launch starts clean and tests
/// can opt into fixtures via `-seed <name>`.
enum UITestSeed {
    static func apply(args: [String], context ctx: ModelContext) {
        let seeds = seedNames(in: args)
        if seeds.contains("priorBench") { seedPriorBench(ctx) }
        if seeds.contains("history") { seedHistory(ctx) }
        // Unified strength + cardio history (field-testing Round 4 A4).
        if seeds.contains("historyMixed") { seedHistory(ctx); seedCardioWalk(ctx) }
        if seeds.contains("coachWhyMixedHistory") { seedCoachWhyMixedHistory(ctx) }
        if seeds.contains("coachYesterdayMixedHistory") { seedCoachYesterdayMixedHistory(ctx) }
        if seeds.contains("coachAerobicGap") { seedCoachAerobicGap(ctx) }
        if seeds.contains("coachCyclePreference") { seedCoachAerobicGap(ctx); UserDefaults.standard.set(cyclePreferenceJSON(), forKey: "settings.coachPreferenceProfile") }
        if seeds.contains("coachLowerBodyRecovery") { seedCoachLowerBodyRecovery(ctx) }
        // Coach Start routing seeds (audio/coach routing plan §D5). Boxing wins among
        // moderate-aerobic candidates by id sort; run wins via a stored preference;
        // strength wins when aerobic is met but strength days are missing.
        if seeds.contains("coachBoxingPrimary") { seedCoachAerobicGap(ctx) }
        if seeds.contains("coachRunPrimary") { seedCoachAerobicGap(ctx); UserDefaults.standard.set(runPreferenceJSON(), forKey: "settings.coachPreferenceProfile") }
        if seeds.contains("coachStrengthPrimary") { seedCoachStrengthPrimary(ctx) }
    }

    private static func seedNames(in args: [String]) -> Set<String> {
        var result: Set<String> = []
        var i = 0
        while i < args.count {
            if args[i] == "-seed", i + 1 < args.count { result.insert(args[i + 1]) }
            i += 1
        }
        return result
    }

    /// A prior Bench Press session at 100 kg × 5 (for last-time / PR tests).
    private static func seedPriorBench(_ ctx: ModelContext) {
        let bench = (try? WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx))
        guard let bench else { return }
        let prior = WorkoutSession(title: "Push Day", date: Date(timeIntervalSinceNow: -3 * 86_400))
        ctx.insert(prior)
        for (i, reps) in [5, 5, 4].enumerated() {
            ctx.insert(SetEntry(weight: 100, reps: reps, order: i,
                                completedAt: prior.date, session: prior, exercise: bench))
        }
        try? ctx.save()
    }

    /// A few weeks of varied sessions for Trends/History UI tests.
    private static func seedHistory(_ ctx: ModelContext) {
        let bench = try? WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        let squat = try? WorkoutRepository.findOrCreateExercise(named: "Back Squat", category: .legs, in: ctx)
        guard let bench, let squat else { return }
        let weeks: [(Int, Double, Double)] = [(28, 90, 120), (21, 92.5, 125), (14, 95, 130), (7, 97.5, 135), (1, 100, 140)]
        for (daysAgo, benchKg, squatKg) in weeks {
            let s = WorkoutSession(title: "Session", date: Date(timeIntervalSinceNow: -Double(daysAgo) * 86_400))
            ctx.insert(s)
            for i in 0..<3 {
                ctx.insert(SetEntry(weight: benchKg, reps: 5, order: i, completedAt: s.date, session: s, exercise: bench))
            }
            for i in 0..<3 {
                ctx.insert(SetEntry(weight: squatKg, reps: 5, order: 3 + i, completedAt: s.date, session: s, exercise: squat))
            }
        }
        try? ctx.save()
    }

    /// One finished walk (10 days ago — between two seeded sessions) with HR
    /// samples, so the unified history list has both kinds and a cardio summary
    /// can render its HR chart.
    private static func seedCardioWalk(_ ctx: ModelContext) {
        let start = Date(timeIntervalSinceNow: -10 * 86_400)
        let c = CardioWorkout(type: .walk, start: start, end: start.addingTimeInterval(1800),
                               distance: 2200, activeEnergy: 140, avgHeartRate: 118,
                               maxHeartRate: 135, source: .iphone)
        ctx.insert(c)
        for (t, bpm) in [(0.0, 100.0), (300.0, 115.0), (600.0, 120.0), (1200.0, 125.0), (1800.0, 118.0)] {
            ctx.insert(HRSample(t: t, bpm: bpm, cardio: c))
        }
        try? ctx.save()
    }

    /// One completed strength session this week + one completed cardio worth 18
    /// moderate-equivalent minutes. Coach should select aerobic because the target
    /// is behind.
    private static func seedCoachWhyMixedHistory(_ ctx: ModelContext) {
        let bench = try? WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        guard let bench else { return }
        // Completed strength session 2 hours ago
        let now = Date()
        let strengthDate = now.addingTimeInterval(-2 * 3600)
        let s = WorkoutSession(title: "Push Day", date: strengthDate)
        s.endedAt = strengthDate.addingTimeInterval(1800)
        ctx.insert(s)
        for i in 0..<3 {
            ctx.insert(SetEntry(weight: 80, reps: 8, order: i, rpe: 8,
                                completedAt: strengthDate, session: s, exercise: bench))
        }
        // Completed cardio yesterday worth 18 mod-eq minutes
        let cardioStart = now.addingTimeInterval(-26 * 3600)
        let c = CardioWorkout(type: .run, start: cardioStart,
                               end: cardioStart.addingTimeInterval(18 * 60),
                               avgHeartRate: 135, source: .iphone)
        ctx.insert(c)
        try? ctx.save()
    }

    /// Strength floor met, aerobic minutes behind, no lower-body collision.
    private static func seedCoachAerobicGap(_ ctx: ModelContext) {
        let bench = try? WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        let row = try? WorkoutRepository.findOrCreateExercise(named: "Barbell Row", category: .pull, in: ctx)
        guard let bench, let row else { return }
        let now = Date()
        // Two strength sessions this week (floor met)
        let s1 = WorkoutSession(title: "Upper 1", date: now.addingTimeInterval(-4 * 86400))
        s1.endedAt = s1.date.addingTimeInterval(1800)
        ctx.insert(s1)
        for i in 0..<3 {
            ctx.insert(SetEntry(weight: 80, reps: 8, order: i, rpe: 8,
                                completedAt: s1.date, session: s1, exercise: bench))
        }
        let s2 = WorkoutSession(title: "Upper 2", date: now.addingTimeInterval(-6 * 86400))
        s2.endedAt = s2.date.addingTimeInterval(1800)
        ctx.insert(s2)
        for i in 0..<3 {
            ctx.insert(SetEntry(weight: 60, reps: 10, order: i, rpe: 8,
                                completedAt: s2.date, session: s2, exercise: row))
        }
        try? ctx.save()
    }

    /// Recent hard lower-body strength (squat within 24h), aerobic target behind.
    /// Verifies that hard/moderate run is not primary.
    private static func seedCoachLowerBodyRecovery(_ ctx: ModelContext) {
        let squat = try? WorkoutRepository.findOrCreateExercise(named: "Back Squat", category: .legs, in: ctx)
        guard let squat else { return }
        let now = Date()
        let s = WorkoutSession(title: "Leg Day", date: now.addingTimeInterval(-6 * 3600))
        s.endedAt = s.date.addingTimeInterval(3600)
        ctx.insert(s)
        for i in 0..<5 {
            ctx.insert(SetEntry(weight: 120, reps: 5, order: i, rpe: 9,
                                completedAt: s.date, session: s, exercise: squat))
        }
        try? ctx.save()
    }

    /// Mixed history with the most recent strength + cardio both *yesterday*, and
    /// older strength + cardio the previous week. Verifies "Why this today" surfaces
    /// the yesterday events as last-strength / last-cardio (not last week's).
    private static func seedCoachYesterdayMixedHistory(_ ctx: ModelContext) {
        let bench = try? WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        let squat = try? WorkoutRepository.findOrCreateExercise(named: "Back Squat", category: .legs, in: ctx)
        guard let bench, let squat else { return }
        let now = Date()
        // Older strength (previous week).
        let oldS = WorkoutSession(title: "Leg Day", date: now.addingTimeInterval(-8 * 86400))
        oldS.endedAt = oldS.date.addingTimeInterval(1800)
        ctx.insert(oldS)
        for i in 0..<3 {
            ctx.insert(SetEntry(weight: 100, reps: 5, order: i, rpe: 8,
                                completedAt: oldS.date, session: oldS, exercise: squat))
        }
        // Older cardio (previous week).
        let oldCStart = now.addingTimeInterval(-9 * 86400)
        ctx.insert(CardioWorkout(type: .walk, start: oldCStart, end: oldCStart.addingTimeInterval(1800),
                                 avgHeartRate: 110, source: .iphone))
        // Strength yesterday (Bench).
        let yS = WorkoutSession(title: "Push Day", date: now.addingTimeInterval(-26 * 3600))
        yS.endedAt = yS.date.addingTimeInterval(1800)
        ctx.insert(yS)
        for i in 0..<3 {
            ctx.insert(SetEntry(weight: 80, reps: 8, order: i, rpe: 8,
                                completedAt: yS.date, session: yS, exercise: bench))
        }
        // Cardio yesterday (Run), 30 min moderate.
        let yCStart = now.addingTimeInterval(-25 * 3600)
        ctx.insert(CardioWorkout(type: .run, start: yCStart, end: yCStart.addingTimeInterval(1800),
                                 avgHeartRate: 135, source: .iphone))
        try? ctx.save()
    }

    /// Aerobic floor met (≥150 mod-eq today), no strength this week → Coach picks
    /// strength. All cardio is dated today so the week boundary can't move it out.
    private static func seedCoachStrengthPrimary(_ ctx: ModelContext) {
        let now = Date()
        for hoursAgo in [2.0, 4.0, 6.0] {
            let start = now.addingTimeInterval(-hoursAgo * 3600 - 3600)
            ctx.insert(CardioWorkout(type: .run, start: start, end: start.addingTimeInterval(3600),
                                     avgHeartRate: 135, source: .iphone))  // 60 min moderate = 60 mod-eq
        }
        try? ctx.save()
    }

    private static func runPreferenceJSON() -> Data {
        // `updatedAt` is encoded as a Double (JSONDecoder's default `.deferredToDate`
        // strategy — seconds since 2001), NOT an ISO8601 string, or decoding fails
        // silently and the preference is dropped.
        let json = """
        {"version":1,"aerobicPreferences":[{"intent":"moderateAerobic","modality":"run","score":3,"updatedAt":772600000}],"strengthPreferences":[],"avoidedTags":[],"selectionEvents":[]}
        """
        return json.data(using: .utf8)!
    }

    private static func cyclePreferenceJSON() -> Data {
        let json = """
        {"version":1,"aerobicPreferences":[{"intent":"moderateAerobic","modality":"cycle","score":3,"updatedAt":"2026-06-23T14:00:00Z"}],"strengthPreferences":[],"avoidedTags":[],"selectionEvents":[]}
        """
        return json.data(using: .utf8)!
    }
}
