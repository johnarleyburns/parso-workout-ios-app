import XCTest
import SwiftData
@testable import CadenceCore

@MainActor
final class WorkoutPlanTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    // MARK: Catalog integrity

    func testStrengthPresetCatalogHasStableUniqueKeys() {
        XCTAssertFalse(StrengthPresets.all.isEmpty)
        let keys = StrengthPresets.all.map(\.id)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testEveryPresetMovementExistsInLibrary() {
        let library = Set(ExerciseLibrary.starter.map { $0.name.lowercased() })
        for plan in StrengthPresets.all {
            for item in plan.items {
                XCTAssertTrue(library.contains(item.movement.lowercased()),
                              "\(plan.name): movement '\(item.movement)' missing from ExerciseLibrary")
            }
        }
    }

    func testSchemeSummaryIsStrength() {
        // Strength is the only scheme after the CrossFit removal (strength pivot P1).
        let push = StrengthPresets.all.first { $0.id == "preset-push" }!
        XCTAssertEqual(push.schemeSummary, "Strength")
    }

    func testMovementNamesDeduplicateInOrder() {
        // A movement used twice appears once, in first-appearance order.
        let plan = WorkoutPlan(id: "t", name: "T", source: .strengthPreset, scheme: .strength,
                               items: [
                                   PlanItem(id: 0, movement: "Back Squat", reps: 5, targetSets: 3),
                                   PlanItem(id: 1, movement: "Bench Press", reps: 5, targetSets: 3),
                                   PlanItem(id: 2, movement: "Back Squat", reps: 5, targetSets: 2),
                               ])
        XCTAssertEqual(plan.movementNames, ["Back Squat", "Bench Press"])
    }

    // MARK: Resolution + launch

    func testPlanCatalogResolvesStrengthPresets() {
        XCTAssertEqual(PlanCatalog.plan(forKey: "preset-5x5-1a")?.name, "5×5 Week 1A")
        XCTAssertNil(PlanCatalog.plan(forKey: "nope"))
    }

    // Strength pivot P1 — a removed CrossFit benchmark key no longer resolves; the
    // session falls back to rendering read-only from its stored title.
    func testLegacyCrossFitKeyResolvesToNil() {
        XCTAssertNil(PlanCatalog.plan(forKey: "fran"))
        XCTAssertNil(PlanCatalog.plan(forKey: "cindy"))
    }

    // round4b feedback #1 — strength presets ("Start from Library") resolve,
    // carry the .strength scheme, and keep a plain (un-prefixed) title.
    func testStrengthPresetsResolveAndAreStrength() throws {
        XCTAssertFalse(StrengthPresets.all.isEmpty)
        // 5×5 is now four alternating days (feedback batch 3); 1A is Squat/Bench/Row.
        let fiveByFive = try XCTUnwrap(PlanCatalog.plan(forKey: "preset-5x5-1a"))
        XCTAssertEqual(fiveByFive.name, "5×5 Week 1A")
        XCTAssertEqual(fiveByFive.displayTitle, "5×5 Week 1A")  // plain name, no prefix
        XCTAssertEqual(fiveByFive.scheme, .strength)
        XCTAssertEqual(fiveByFive.movementNames, ["Back Squat", "Bench Press", "Barbell Row"])
        XCTAssertFalse(fiveByFive.flexibleScheme, "a fixed program needs no rep-scheme chooser")
        // Every preset item carries target sets/reps.
        for plan in StrengthPresets.all {
            XCTAssertEqual(plan.source, .strengthPreset)
            for item in plan.items {
                XCTAssertNotNil(item.targetSets)
                XCTAssertNotNil(item.reps)
            }
        }
    }

    // feedback batch 3 — Olympic split into three focused days; split templates
    // are flexible (their scheme is chosen at launch).
    func testStrengthPresetVariantsAndFlexibility() throws {
        XCTAssertEqual(PlanCatalog.plan(forKey: "preset-oly-snatch")?.name, "Olympic Snatch Day")
        let snatch = try XCTUnwrap(PlanCatalog.plan(forKey: "preset-oly-snatch"))
        XCTAssertEqual(snatch.items.map(\.movement), ["Snatch"])
        XCTAssertEqual(snatch.items.first?.targetSets, 20)
        XCTAssertFalse(snatch.flexibleScheme)
        XCTAssertTrue(try XCTUnwrap(PlanCatalog.plan(forKey: "preset-push")).flexibleScheme)
        XCTAssertTrue(try XCTUnwrap(PlanCatalog.plan(forKey: "preset-cali-pull")).flexibleScheme)
        // The 5×5 days and Olympic days all resolve.
        for id in ["preset-5x5-1a", "preset-5x5-1b", "preset-5x5-2a", "preset-5x5-2b",
                   "preset-oly-snatch", "preset-oly-cj", "preset-oly-mixed"] {
            XCTAssertNotNil(PlanCatalog.plan(forKey: id), "\(id) should resolve")
        }
    }

    // feedback batch 3 — launching a flexible template with a chosen rep ladder
    // stamps the ladder on the session for the planned-card prescription.
    func testStartSessionWithRepLadderStampsLadder() throws {
        let ctx = try makeContext()
        let push = try XCTUnwrap(PlanCatalog.plan(forKey: "preset-push"))
        let session = try WorkoutRepository.startSession(from: push, repLadder: [12, 10, 8], in: ctx)
        XCTAssertEqual(session.plannedRepLadder, [12, 10, 8])
    }

    func testStartSessionFromPlanPreloadsMovements() throws {
        let ctx = try makeContext()
        let fiveByFive = try XCTUnwrap(PlanCatalog.plan(forKey: "preset-5x5-1a"))
        let session = try WorkoutRepository.startSession(from: fiveByFive, in: ctx)
        // Strength presets keep their plain name (no "CrossFit –" prefix).
        XCTAssertEqual(session.title, "5×5 Week 1A")
        XCTAssertEqual(session.planKey, "preset-5x5-1a")
        XCTAssertEqual(session.plannedExerciseNames, ["Back Squat", "Bench Press", "Barbell Row"])
        // The movements exist as exercises after launch.
        let names = try WorkoutRepository.allExercises(ctx).map(\.name)
        XCTAssertTrue(names.contains("Back Squat"))
        XCTAssertTrue(names.contains("Bench Press"))
    }

    // MARK: Library seeding upgrade path

    func testSeedAddsFunctionalMovementsToOlderStore() throws {
        let ctx = try makeContext()
        // Simulate an older store missing the newer movements by seeding only a
        // couple of legacy exercises first.
        ctx.insert(Exercise(name: "Bench Press"))
        try ctx.save()
        let before = try WorkoutRepository.allExercises(ctx).count
        XCTAssertTrue(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
        let after = try WorkoutRepository.allExercises(ctx)
        XCTAssertTrue(after.contains { $0.name == "Back Squat" })
        XCTAssertTrue(after.contains { $0.name == "Bench Press" })
        XCTAssertGreaterThan(after.count, before)
        // Idempotent on a second pass.
        XCTAssertFalse(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
    }
}
