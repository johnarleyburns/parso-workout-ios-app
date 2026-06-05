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
}
