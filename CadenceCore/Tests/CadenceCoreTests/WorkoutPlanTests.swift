#if canImport(SwiftData)
import Testing
import SwiftData
@testable import CadenceCore

@MainActor
struct WorkoutPlanTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    // MARK: Catalog integrity

    @Test func strengthPresetCatalogHasStableUniqueKeys() {
        #expect(!StrengthPresets.all.isEmpty)
        let keys = StrengthPresets.all.map(\.id)
        #expect(Set(keys).count == keys.count)
    }

    @Test func everyPresetMovementExistsInLibrary() {
        let library = Set(ExerciseLibrary.starter.map { $0.name.lowercased() })
        for plan in StrengthPresets.all {
            for item in plan.items {
                #expect(library.contains(item.movement.lowercased()),
                              "\(plan.name): movement '\(item.movement)' missing from ExerciseLibrary")
            }
        }
    }

    @Test func schemeSummaryIsStrength() {
        // Strength is the only scheme after the CrossFit removal (strength pivot P1).
        let push = StrengthPresets.all.first { $0.id == "preset-push" }!
        #expect(push.schemeSummary == "Strength")
    }

    @Test func movementNamesDeduplicateInOrder() {
        // A movement used twice appears once, in first-appearance order.
        let plan = WorkoutPlan(id: "t", name: "T", source: .strengthPreset, scheme: .strength,
                               items: [
                                   PlanItem(id: 0, movement: "Back Squat", reps: 5, targetSets: 3),
                                   PlanItem(id: 1, movement: "Bench Press", reps: 5, targetSets: 3),
                                   PlanItem(id: 2, movement: "Back Squat", reps: 5, targetSets: 2),
                               ])
        #expect(plan.movementNames == ["Back Squat", "Bench Press"])
    }

    // MARK: Resolution + launch

    @Test func planCatalogResolvesStrengthPresets() {
        #expect(PlanCatalog.plan(forKey: "preset-5x5-1a")?.name == "5×5 Week 1A")
        #expect(PlanCatalog.plan(forKey: "nope") == nil)
    }

    // Strength pivot P1 — a removed CrossFit benchmark key no longer resolves; the
    // session falls back to rendering read-only from its stored title.
    @Test func legacyCrossFitKeyResolvesToNil() {
        #expect(PlanCatalog.plan(forKey: "fran") == nil)
        #expect(PlanCatalog.plan(forKey: "cindy") == nil)
    }

    // round4b feedback #1 — strength presets ("Start from Library") resolve,
    // carry the .strength scheme, and keep a plain (un-prefixed) title.
    @Test func strengthPresetsResolveAndAreStrength() throws {
        #expect(!StrengthPresets.all.isEmpty)
        // 5×5 is now four alternating days (feedback batch 3); 1A is Squat/Bench/Row.
        let fiveByFive = try #require(PlanCatalog.plan(forKey: "preset-5x5-1a"))
        #expect(fiveByFive.name == "5×5 Week 1A")
        #expect(fiveByFive.displayTitle == "5×5 Week 1A")  // plain name, no prefix
        #expect(fiveByFive.scheme == .strength)
        #expect(fiveByFive.movementNames == ["Back Squat", "Bench Press", "Barbell Row"])
        #expect(!fiveByFive.flexibleScheme, "a fixed program needs no rep-scheme chooser")
        // Every preset item carries target sets/reps.
        for plan in StrengthPresets.all {
            #expect(plan.source == .strengthPreset)
            for item in plan.items {
                #expect(item.targetSets != nil)
                #expect(item.reps != nil)
            }
        }
    }

    // feedback batch 3 — Olympic split into three focused days; split templates
    // are flexible (their scheme is chosen at launch).
    @Test func strengthPresetVariantsAndFlexibility() throws {
        #expect(PlanCatalog.plan(forKey: "preset-oly-snatch")?.name == "Olympic Snatch Day")
        let snatch = try #require(PlanCatalog.plan(forKey: "preset-oly-snatch"))
        #expect(snatch.items.map(\.movement) == ["Snatch"])
        #expect(snatch.items.first?.targetSets == 20)
        #expect(!snatch.flexibleScheme)
        #expect(try #require(PlanCatalog.plan(forKey: "preset-push")).flexibleScheme)
        #expect(try #require(PlanCatalog.plan(forKey: "preset-cali-pull")).flexibleScheme)
        // The 5×5 days and Olympic days all resolve.
        for id in ["preset-5x5-1a", "preset-5x5-1b", "preset-5x5-2a", "preset-5x5-2b",
                   "preset-oly-snatch", "preset-oly-cj", "preset-oly-mixed"] {
            #expect(PlanCatalog.plan(forKey: id) != nil, "\(id) should resolve")
        }
    }

    // feedback batch 3 — launching a flexible template with a chosen rep ladder
    // stamps the ladder on the session for the planned-card prescription.
    @Test func startSessionWithRepLadderStampsLadder() throws {
        let ctx = try makeContext()
        let push = try #require(PlanCatalog.plan(forKey: "preset-push"))
        let session = try WorkoutRepository.startSession(from: push, repLadder: [12, 10, 8], in: ctx)
        #expect(session.plannedRepLadder == [12, 10, 8])
    }

    @Test func startSessionFromPlanPreloadsMovements() throws {
        let ctx = try makeContext()
        let fiveByFive = try #require(PlanCatalog.plan(forKey: "preset-5x5-1a"))
        let session = try WorkoutRepository.startSession(from: fiveByFive, in: ctx)
        // Strength presets keep their plain name (no "CrossFit –" prefix).
        #expect(session.title == "5×5 Week 1A")
        #expect(session.planKey == "preset-5x5-1a")
        #expect(session.plannedExerciseNames == ["Back Squat", "Bench Press", "Barbell Row"])
        // The movements exist as exercises after launch.
        let names = try WorkoutRepository.allExercises(ctx).map(\.name)
        #expect(names.contains("Back Squat"))
        #expect(names.contains("Bench Press"))
    }

    // MARK: Library seeding upgrade path

    @Test func seedAddsFunctionalMovementsToOlderStore() throws {
        let ctx = try makeContext()
        // Simulate an older store missing the newer movements by seeding only a
        // couple of legacy exercises first.
        ctx.insert(Exercise(name: "Bench Press"))
        try ctx.save()
        let before = try WorkoutRepository.allExercises(ctx).count
        #expect(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
        let after = try WorkoutRepository.allExercises(ctx)
        #expect(after.contains { $0.name == "Back Squat" })
        #expect(after.contains { $0.name == "Bench Press" })
        #expect(after.count > before)
        // Idempotent on a second pass.
        #expect(!(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)))
    }
}
#endif
