import XCTest
import SwiftData
@testable import CadenceCore

@MainActor
final class WorkoutPlanTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    // MARK: Catalog integrity

    func testGirlsCatalogHasFifteen() {
        XCTAssertEqual(BenchmarkWorkouts.girls.count, 15)
        // Stable, unique keys.
        let keys = BenchmarkWorkouts.girls.map(\.id)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testEveryBenchmarkMovementExistsInLibrary() {
        let library = Set(ExerciseLibrary.starter.map { $0.name.lowercased() })
        for plan in BenchmarkWorkouts.girls {
            for item in plan.items {
                XCTAssertTrue(library.contains(item.movement.lowercased()),
                              "\(plan.name): movement '\(item.movement)' missing from ExerciseLibrary")
            }
        }
    }

    func testSchemeSummaries() {
        func summary(_ key: String) -> String {
            BenchmarkWorkouts.girls.first { $0.id == key }!.schemeSummary
        }
        XCTAssertEqual(summary("fran"), "21-15-9 for time")
        XCTAssertEqual(summary("annie"), "50-40-30-20-10 for time")
        XCTAssertEqual(summary("grace"), "For time")
        XCTAssertEqual(summary("cindy"), "AMRAP 20 min")
        XCTAssertEqual(summary("chelsea"), "EMOM 30 min")
        XCTAssertEqual(summary("barbara"), "5 rounds for time · 3 min rest")
        XCTAssertEqual(summary("helen"), "3 rounds for time")
    }

    func testMovementNamesDeduplicateInOrder() {
        let cindy = BenchmarkWorkouts.girls.first { $0.id == "cindy" }!
        XCTAssertEqual(cindy.movementNames, ["Pull-Up", "Push-Up", "Air Squat"])
        // Jackie repeats nothing but mixes distance + load items.
        let jackie = BenchmarkWorkouts.girls.first { $0.id == "jackie" }!
        XCTAssertEqual(jackie.movementNames, ["Rowing Machine", "Thruster", "Pull-Up"])
    }

    func testRxLoadsPresentWhereExpected() {
        let fran = BenchmarkWorkouts.girls.first { $0.id == "fran" }!
        let thruster = fran.items.first { $0.movement == "Thruster" }!
        XCTAssertEqual(thruster.loadLb, 95)
        XCTAssertEqual(thruster.loadLbFemale, 65)
        let pullup = fran.items.first { $0.movement == "Pull-Up" }!
        XCTAssertNil(pullup.loadLb)
    }

    // MARK: Resolution + launch

    func testPlanCatalogResolvesKeys() {
        XCTAssertEqual(PlanCatalog.plan(forKey: "fran")?.name, "Fran")
        XCTAssertNil(PlanCatalog.plan(forKey: "nope"))
    }

    func testStartSessionFromPlanPreloadsMovements() throws {
        let ctx = try makeContext()
        let fran = PlanCatalog.plan(forKey: "fran")!
        let session = try WorkoutRepository.startSession(from: fran, in: ctx)
        XCTAssertEqual(session.title, "Fran")
        XCTAssertEqual(session.planKey, "fran")
        XCTAssertEqual(session.plannedExerciseNames, ["Thruster", "Pull-Up"])
        // Both movements now exist as exercises.
        let names = try WorkoutRepository.allExercises(ctx).map(\.name)
        XCTAssertTrue(names.contains("Thruster"))
        XCTAssertTrue(names.contains("Pull-Up"))
    }

    // MARK: Library seeding upgrade path

    func testSeedAddsCrossFitMovementsToOlderStore() throws {
        let ctx = try makeContext()
        // Simulate an older store missing the new movements by seeding only a
        // couple of legacy exercises first.
        ctx.insert(Exercise(name: "Bench Press"))
        try ctx.save()
        let before = try WorkoutRepository.allExercises(ctx).count
        XCTAssertTrue(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
        let after = try WorkoutRepository.allExercises(ctx)
        XCTAssertTrue(after.contains { $0.name == "Wall Ball" })
        XCTAssertTrue(after.contains { $0.name == "Double-Under" })
        XCTAssertGreaterThan(after.count, before)
        // Idempotent on a second pass.
        XCTAssertFalse(try WorkoutRepository.seedStarterLibraryIfNeeded(ctx))
    }
}
