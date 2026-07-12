import Foundation
import SwiftData
import CadenceCore
import CadenceFixtures

/// Deterministic data seeding for UI tests, driven by launch arguments. The
/// store is in-memory in UI-test mode, so each launch starts clean and tests
/// can opt into fixtures via `-seed <name>`.
///
/// The seed graphs themselves live in `CadenceFixtures` so headless `swift test`
/// can seed the *same* data (test-pyramid plan, 2026-07-12). This dispatcher just
/// maps launch-argument names to those builders and applies the UI-test-only
/// UserDefaults preferences.
enum UITestSeed {
    static func apply(args: [String], context ctx: ModelContext) {
        let seeds = seedNames(in: args)
        if seeds.contains("priorBench") { Fixtures.priorBench(into: ctx) }
        if seeds.contains("history") { Fixtures.history(into: ctx) }
        // Unified strength + cardio history (field-testing Round 4 A4).
        if seeds.contains("historyMixed") { Fixtures.historyMixed(into: ctx) }
        if seeds.contains("coachWhyMixedHistory") { Fixtures.coachWhyMixedHistory(into: ctx) }
        if seeds.contains("coachYesterdayMixedHistory") { Fixtures.coachYesterdayMixedHistory(into: ctx) }
        if seeds.contains("coachAerobicGap") { Fixtures.coachAerobicGap(into: ctx) }
        if seeds.contains("coachCyclePreference") { Fixtures.coachAerobicGap(into: ctx); UserDefaults.standard.set(Fixtures.cyclePreferenceJSON, forKey: "settings.coachPreferenceProfile") }
        if seeds.contains("coachLowerBodyRecovery") { Fixtures.coachLowerBodyRecovery(into: ctx) }
        if seeds.contains("coachTwoADayStrengthDone") { Fixtures.coachTwoADayStrengthDone(into: ctx) }
        // Coach Start routing seeds (audio/coach routing plan §D5). Boxing wins among
        // moderate-aerobic candidates by id sort; run wins via a stored preference;
        // strength wins when aerobic is met but strength days are missing.
        if seeds.contains("coachBoxingPrimary") { Fixtures.coachAerobicGap(into: ctx) }
        if seeds.contains("coachRunPrimary") { Fixtures.coachAerobicGap(into: ctx); UserDefaults.standard.set(Fixtures.runPreferenceJSON, forKey: "settings.coachPreferenceProfile") }
        if seeds.contains("coachStrengthPrimary") { Fixtures.coachStrengthPrimary(into: ctx) }
        if seeds.contains("coachWednesdayComplete") { Fixtures.coachWednesdayComplete(into: ctx) }
        if seeds.contains("customExerciseNeedsReassign") { Fixtures.customExerciseNeedsReassign(into: ctx) }
        if seeds.contains("historyPartnerSession") { Fixtures.historyPartnerSession(into: ctx) }
        // Generic "-seed person.<Name>" creates a selectable training partner.
        for seed in seeds where seed.hasPrefix("person.") {
            let name = String(seed.dropFirst("person.".count))
            if !name.isEmpty { _ = try? WorkoutRepository.findOrCreatePerson(named: name, in: ctx) }
        }
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
}
