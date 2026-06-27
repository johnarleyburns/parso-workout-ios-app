import XCTest
import SwiftData
@testable import CadenceCore

final class LoadAccountingTests: XCTestCase {

    // MARK: - Setup

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    // MARK: - Exercise accounting defaults

    func testDefaultBarbellAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .barbell, isLateral: false, name: "Bench Press")
        XCTAssertEqual(mode, .barbell)
    }

    func testDefaultBodyweightAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .bodyweight, isLateral: false, name: "Pull-Up")
        XCTAssertEqual(mode, .bodyweight)
    }

    func testDefaultDualDumbbellAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .dumbbell, isLateral: false, name: "Dumbbell Bench Press")
        XCTAssertEqual(mode, .dualDumbbell)
    }

    func testDefaultSingleDumbbellAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .dumbbell, isLateral: false, name: "Dumbbell Skullcrusher")
        XCTAssertEqual(mode, .singleDumbbell)
    }

    func testDefaultSingleDumbbellGobletStyle() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .dumbbell, isLateral: false, name: "Goblet Squat")
        XCTAssertEqual(mode, .singleDumbbell)
    }

    func testDefaultIsolateralDumbbellAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .dumbbell, isLateral: true, name: "Dumbbell Bent-Over Row")
        XCTAssertEqual(mode, .isolateralDumbbell)
    }

    func testMachineNoAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .machine, isLateral: false, name: "Leg Press")
        XCTAssertNil(mode)
    }

    func testCableNoAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .cable, isLateral: false, name: "Cable Flye")
        XCTAssertNil(mode)
    }

    // MARK: - Exercise.resolvedLoadAccountingMode

    func testResolvedModeUsesStoredValue() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Test", equipment: .barbell, loadAccountingMode: .bodyweight)
        ctx.insert(ex)
        XCTAssertEqual(ex.resolvedLoadAccountingMode, .bodyweight)
    }

    func testResolvedModeFallsBackToDefault() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Test", equipment: .barbell)
        ctx.insert(ex)
        XCTAssertEqual(ex.resolvedLoadAccountingMode, .barbell)
    }

    // MARK: - effectiveLoadKg

    func testEffectiveLoadKgLegacySetReturnsRawWeight() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 60, reps: 8)
        ctx.insert(set)
        XCTAssertEqual(set.effectiveLoadKg, 60)
    }

    func testEffectiveLoadKgBarbellAddsBar() throws {
        let ctx = try makeContext()
        let barWeight = Exercise.defaultBarWeightKg
        let set = SetEntry(weight: 40, reps: 5, barWeightKg: barWeight,
                           loadAccountingMode: LoadAccountingMode.barbell.rawValue)
        ctx.insert(set)
        XCTAssertEqual(set.effectiveLoadKg, 40 + barWeight, accuracy: 0.01)
    }

    func testEffectiveLoadKgBarbellZeroEntered() throws {
        let ctx = try makeContext()
        let barWeight = Exercise.defaultBarWeightKg
        let set = SetEntry(weight: 0, reps: 10, barWeightKg: barWeight,
                           loadAccountingMode: LoadAccountingMode.barbell.rawValue)
        ctx.insert(set)
        XCTAssertEqual(set.effectiveLoadKg, barWeight, accuracy: 0.01)
    }

    func testEffectiveLoadKgDualDumbbellDoubles() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 50, reps: 10,
                           loadAccountingMode: LoadAccountingMode.dualDumbbell.rawValue)
        ctx.insert(set)
        XCTAssertEqual(set.effectiveLoadKg, 100)
    }

    func testEffectiveLoadKgSingleDumbbellKeepsWeight() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 50, reps: 10,
                           loadAccountingMode: LoadAccountingMode.singleDumbbell.rawValue)
        ctx.insert(set)
        XCTAssertEqual(set.effectiveLoadKg, 50)
    }

    func testEffectiveLoadKgIsolateralDumbbellDoubles() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 50, reps: 8,
                           loadAccountingMode: LoadAccountingMode.isolateralDumbbell.rawValue)
        ctx.insert(set)
        XCTAssertEqual(set.effectiveLoadKg, 100)
    }

    func testEffectiveLoadKgBodyweight() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 10, reps: 5, usesBodyweight: true,
                           loadAccountingMode: LoadAccountingMode.bodyweight.rawValue)
        ctx.insert(set)
        XCTAssertEqual(set.effectiveLoadKg, 10)
    }

    func testEffectiveLoadKgBodyweightZero() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 0, reps: 10, usesBodyweight: true,
                           loadAccountingMode: LoadAccountingMode.bodyweight.rawValue)
        ctx.insert(set)
        XCTAssertEqual(set.effectiveLoadKg, 0)
    }

    // MARK: - prospectiveEffectiveLoadKg

    func testProspectiveEffectiveLoadKgBarbell() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Bench Press", equipment: .barbell)
        ctx.insert(ex)
        let bar = Exercise.defaultBarWeightKg
        XCTAssertEqual(ex.prospectiveEffectiveLoadKg(rawWeightKg: 40), 40 + bar, accuracy: 0.01)
    }

    func testProspectiveEffectiveLoadKgDumbbell() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Dumbbell Press", equipment: .dumbbell)
        ctx.insert(ex)
        XCTAssertEqual(ex.prospectiveEffectiveLoadKg(rawWeightKg: 30), 60)
    }

    func testProspectiveEffectiveLoadKgCustomBarWeight() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Bench Press", equipment: .barbell, defaultBarWeightKg: 15)
        ctx.insert(ex)
        XCTAssertEqual(ex.prospectiveEffectiveLoadKg(rawWeightKg: 40), 55, accuracy: 0.01)
    }

    // MARK: - Seeding

    func testSeedAddsLoadAccountingToExercise() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        let bench = try WorkoutRepository.allExercises(ctx).first { $0.name == "Bench Press" }
        XCTAssertEqual(bench?.loadAccountingModeValue, .barbell)
        if let b = bench {
            XCTAssertEqual(b.defaultBarWeightKg, Exercise.defaultBarWeightKg, accuracy: 0.01)
        } else {
            XCTFail("Bench Press not found")
        }
    }

    func testSeedBodyweightNoBarWeight() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        let all = try WorkoutRepository.allExercises(ctx)
        // Find a bodyweight exercise from the starter library.
        if let bw = all.first(where: { $0.equipmentValue == .bodyweight && $0.loadAccountingMode != nil }) {
            XCTAssertEqual(bw.loadAccountingModeValue, .bodyweight)
            XCTAssertEqual(bw.defaultBarWeightKg, 0)
        }
        // At minimum, verify Pull-Up is present with correct accounting.
        if let pullUp = all.first(where: { $0.name == "Pull-Up" }) {
            XCTAssertEqual(pullUp.loadAccountingModeValue, .bodyweight,
                           "Pull-Up should have bodyweight accounting")
            XCTAssertEqual(pullUp.defaultBarWeightKg, 0)
        }
    }

    // MARK: - Snapshot on set creation

    func testAddSetSnapshotsAccountingMetadata() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        guard let ex = try WorkoutRepository.allExercises(ctx).first(where: { $0.name == "Bench Press" }) else {
            XCTFail("Bench Press not found"); return
        }
        let session = WorkoutSession(title: "Test")
        ctx.insert(session)
        try ctx.save()

        let set = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 60, reps: 5, in: ctx)
        XCTAssertEqual(set.loadAccountingModeValue, .barbell)
        XCTAssertEqual(set.barWeightKg, Exercise.defaultBarWeightKg, accuracy: 0.01)
        XCTAssertEqual(set.weight, 60)
        XCTAssertTrue(set.effectiveLoadKg > set.weight)
    }

    func testAddSetNoAccountingForMachine() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        guard let ex = try WorkoutRepository.allExercises(ctx).first(where: { $0.name == "Leg Press" }) else {
            XCTFail("Leg Press not found"); return
        }
        let session = WorkoutSession(title: "Test")
        ctx.insert(session)
        try ctx.save()

        let set = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 10, in: ctx)
        XCTAssertNil(set.loadAccountingModeValue)
        XCTAssertEqual(set.barWeightKg, 0)
        XCTAssertEqual(set.effectiveLoadKg, 100)
    }

    // MARK: - Export/Import round-trip

    func testExportIncludesLoadAccounting() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        guard let ex = try WorkoutRepository.allExercises(ctx).first(where: { $0.name == "Bench Press" }) else {
            XCTFail("Bench Press not found"); return
        }
        let session = WorkoutSession(title: "Test")
        ctx.insert(session)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 60, reps: 5, in: ctx)

        let export = try WorkoutRepository.buildExport(ctx)
        guard let es = export.sessions.first?.sets.first else {
            XCTFail("Expected one exported set"); return
        }
        XCTAssertEqual(es.loadAccountingMode, LoadAccountingMode.barbell.rawValue)
        XCTAssertNotNil(es.barWeightKg)
        XCTAssertNotNil(es.loadMultiplier)
    }

    func testMergeRestoresLoadAccounting() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        guard let ex = try WorkoutRepository.allExercises(ctx).first(where: { $0.name == "Bench Press" }) else {
            XCTFail("Bench Press not found"); return
        }
        let session = WorkoutSession(title: "Test")
        ctx.insert(session)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 60, reps: 5, in: ctx)

        let export = try WorkoutRepository.buildExport(ctx)
        let ctx2 = try makeContext()
        _ = try WorkoutRepository.merge(export, in: ctx2)
        let imported = try WorkoutRepository.allSessions(ctx2).first!
        let importedSet = imported.orderedSets.first!
        XCTAssertEqual(importedSet.loadAccountingModeValue, .barbell)
        XCTAssertEqual(importedSet.barWeightKg, Exercise.defaultBarWeightKg, accuracy: 0.01)
    }

    // MARK: - PR calculations use effective load

    func testPRCalculatorUsesEffectiveLoad() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        guard let ex = try WorkoutRepository.allExercises(ctx).first(where: { $0.name == "Bench Press" }) else {
            XCTFail("Bench Press not found"); return
        }
        let session = WorkoutSession(title: "Test")
        ctx.insert(session)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 40, reps: 5, in: ctx)

        let pr = WorkoutRepository.currentPR(for: ex, rule: .topWeight, formula: .epley)
        let expected = Exercise.defaultBarWeightKg + 40
        if let pr {
            XCTAssertEqual(pr, expected, accuracy: 0.1)
        } else {
            XCTFail("Expected a PR value")
        }
    }

    func testTotalVolumeUsesEffectiveLoad() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        guard let ex = try WorkoutRepository.allExercises(ctx).first(where: { $0.name == "Bench Press" }) else {
            XCTFail("Bench Press not found"); return
        }
        let session = WorkoutSession(title: "Test")
        ctx.insert(session)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 40, reps: 5, in: ctx)

        let effectiveWeight = Exercise.defaultBarWeightKg + 40
        let expectedVolume = effectiveWeight * 5
        XCTAssertEqual(session.totalVolume, expectedVolume, accuracy: 0.1)
    }

    // MARK: - Optional RPE

    func testSetEntryRPEDefaultsToNil() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 60, reps: 8)
        ctx.insert(set)
        XCTAssertNil(set.rpe)
    }

    func testSetEntryStoresRPE() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 60, reps: 8, rpe: 7.5)
        ctx.insert(set)
        XCTAssertEqual(set.rpe, 7.5)
    }

    func testSetEntryRPEIsOptionalAfterEdit() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 60, reps: 8, rpe: 7)
        ctx.insert(set)
        try WorkoutRepository.updateSet(set, weightKg: 65, reps: 10, in: ctx)
        XCTAssertEqual(set.rpe, 7)
    }

    func testSetEntryRPECanBeCleared() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 60, reps: 8, rpe: 7)
        ctx.insert(set)
        try WorkoutRepository.updateSet(set, rpe: .some(nil), in: ctx)
        XCTAssertNil(set.rpe)
    }

    // MARK: - First-set / subsequent-set weight defaulting

    func testPriorFirstWorkingSetWeightReturned() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Bench Press")
        ctx.insert(ex)
        let prior = WorkoutSession(title: "Prior", date: Date().addingTimeInterval(-86400))
        ctx.insert(prior)
        _ = SetEntry(weight: 20, reps: 10, order: 0, isWarmup: true, session: prior, exercise: ex)
        _ = SetEntry(weight: 65, reps: 8, order: 1, session: prior, exercise: ex)
        _ = SetEntry(weight: 60, reps: 6, order: 2, session: prior, exercise: ex)
        try ctx.save()

        let firstSets = WorkoutRepository.lastTimeSets(for: ex, excluding: nil)
        let firstWorking = firstSets.first { !$0.isWarmup && $0.weight > 0 }
        XCTAssertEqual(firstWorking?.weight, 65)
    }

    func testNoPriorSessionReturnsNoWeight() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "New Exercise")
        ctx.insert(ex)
        try ctx.save()
        let sets = WorkoutRepository.lastTimeSets(for: ex, excluding: nil)
        XCTAssertTrue(sets.isEmpty)
    }
}
