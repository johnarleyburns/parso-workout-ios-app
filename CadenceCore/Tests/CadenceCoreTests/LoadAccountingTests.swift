#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

struct LoadAccountingTests {
    @Test func allBellModesUseTotalForIsometricAndIsolateralMovements() throws {
        let context = try makeContext()
        for mode: LoadAccountingMode in [.dualDumbbell, .singleDumbbell, .isolateralDumbbell,
                                         .dualKettlebell, .singleKettlebell, .isolateralKettlebell] {
            let exercise = Exercise(name: "Isometric Biceps Curl", loadAccountingMode: mode)
            context.insert(exercise)
            let set = SetEntry(weight: 40, reps: 10, exercise: exercise,
                               loadMultiplier: 2, loadAccountingMode: mode.rawValue)
            context.insert(set)
            #expect(exercise.prospectiveEffectiveLoadKg(rawWeightKg: 40) == 40)
            #expect(set.effectiveLoadKg == 40)
        }
    }

    // MARK: - Setup

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    // MARK: - Exercise accounting defaults

    @Test func defaultBarbellAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .barbell, isLateral: false, name: "Bench Press")
        #expect(mode == .barbell)
    }

    @Test func defaultBodyweightAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .bodyweight, isLateral: false, name: "Pull-Up")
        #expect(mode == .bodyweight)
    }

    @Test func defaultDualDumbbellAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .dumbbell, isLateral: false, name: "Dumbbell Bench Press")
        #expect(mode == .dualDumbbell)
    }

    @Test func defaultSingleDumbbellAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .dumbbell, isLateral: false, name: "Dumbbell Skullcrusher")
        #expect(mode == .singleDumbbell)
    }

    @Test func defaultSingleDumbbellGobletStyle() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .dumbbell, isLateral: false, name: "Goblet Squat")
        #expect(mode == .singleDumbbell)
    }

    @Test func defaultIsolateralDumbbellAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .dumbbell, isLateral: true, name: "Dumbbell Bent-Over Row")
        #expect(mode == .isolateralDumbbell)
    }

    @Test func machineNoAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .machine, isLateral: false, name: "Leg Press")
        #expect(mode == nil)
    }

    @Test func cableNoAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .cable, isLateral: false, name: "Cable Flye")
        #expect(mode == nil)
    }

    // MARK: Phase 4 — Kettlebell accounting

    @Test func defaultDualKettlebellAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .kettlebell, isLateral: false, name: "Double Kettlebell Clean")
        #expect(mode == .dualKettlebell)
    }

    @Test func defaultSingleKettlebellSwing() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .kettlebell, isLateral: false, name: "Kettlebell Swing")
        #expect(mode == .singleKettlebell)
    }

    @Test func defaultSingleKettlebellTurkishGetUp() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .kettlebell, isLateral: false, name: "Turkish Get-Up")
        #expect(mode == .singleKettlebell)
    }

    @Test func defaultIsolateralKettlebellAccounting() {
        let mode = Exercise.defaultLoadAccountingMode(equipment: .kettlebell, isLateral: true, name: "Kettlebell Clean")
        #expect(mode == .isolateralKettlebell)
    }

    @Test func dualKettlebellEffectiveLoad() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Double Kettlebell Press",
                          equipment: .kettlebell,
                          loadAccountingMode: .dualKettlebell)
        ctx.insert(ex)
        let set = SetEntry(weight: 16, reps: 8, exercise: ex,
                           loadAccountingMode: LoadAccountingMode.dualKettlebell.rawValue)
        ctx.insert(set)
        #expect(set.effectiveLoadKg == 16.0)
    }

    @Test func singleKettlebellEffectiveLoad() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Kettlebell Swing",
                          equipment: .kettlebell,
                          loadAccountingMode: .singleKettlebell)
        ctx.insert(ex)
        let set = SetEntry(weight: 24, reps: 10, exercise: ex,
                           loadAccountingMode: LoadAccountingMode.singleKettlebell.rawValue)
        ctx.insert(set)
        #expect(set.effectiveLoadKg == 24.0)
    }

    @Test func prospectiveDoubleKettlebellLoad() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Double Kettlebell Front Squat",
                          equipment: .kettlebell,
                          loadAccountingMode: .dualKettlebell)
        ctx.insert(ex)
        #expect(ex.prospectiveEffectiveLoadKg(rawWeightKg: 20) == 20.0)
    }

    @Test func prospectiveSingleKettlebellLoad() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Kettlebell Snatch",
                          equipment: .kettlebell,
                          loadAccountingMode: .singleKettlebell)
        ctx.insert(ex)
        #expect(ex.prospectiveEffectiveLoadKg(rawWeightKg: 20) == 20.0)
    }

    // MARK: - Exercise.resolvedLoadAccountingMode

    @Test func resolvedModeUsesStoredValue() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Test", equipment: .barbell, loadAccountingMode: .bodyweight)
        ctx.insert(ex)
        #expect(ex.resolvedLoadAccountingMode == .bodyweight)
    }

    @Test func resolvedModeFallsBackToDefault() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Test", equipment: .barbell)
        ctx.insert(ex)
        #expect(ex.resolvedLoadAccountingMode == .barbell)
    }

    // MARK: - effectiveLoadKg

    @Test func effectiveLoadKgLegacySetReturnsRawWeight() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 60, reps: 8)
        ctx.insert(set)
        #expect(set.effectiveLoadKg == 60)
    }

    @Test func effectiveLoadKgBarbellAddsBar() throws {
        let ctx = try makeContext()
        let barWeight = Exercise.defaultBarWeightKg
        let set = SetEntry(weight: 40, reps: 5, barWeightKg: barWeight,
                           loadAccountingMode: LoadAccountingMode.barbell.rawValue)
        ctx.insert(set)
        #expect(abs(set.effectiveLoadKg - (40 + barWeight)) <= 0.01)
    }

    @Test func effectiveLoadKgBarbellZeroEntered() throws {
        let ctx = try makeContext()
        let barWeight = Exercise.defaultBarWeightKg
        let set = SetEntry(weight: 0, reps: 10, barWeightKg: barWeight,
                           loadAccountingMode: LoadAccountingMode.barbell.rawValue)
        ctx.insert(set)
        #expect(abs(set.effectiveLoadKg - barWeight) <= 0.01)
    }

    @Test func effectiveLoadKgDualDumbbellUsesEnteredTotal() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 50, reps: 10,
                           loadAccountingMode: LoadAccountingMode.dualDumbbell.rawValue)
        ctx.insert(set)
        #expect(set.effectiveLoadKg == 50)
    }

    @Test func effectiveLoadKgSingleDumbbellKeepsWeight() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 50, reps: 10,
                           loadAccountingMode: LoadAccountingMode.singleDumbbell.rawValue)
        ctx.insert(set)
        #expect(set.effectiveLoadKg == 50)
    }

    @Test func effectiveLoadKgIsolateralDumbbellUsesEnteredTotal() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 50, reps: 8,
                           loadAccountingMode: LoadAccountingMode.isolateralDumbbell.rawValue)
        ctx.insert(set)
        #expect(set.effectiveLoadKg == 50)
    }

    @Test func legacyLoadMultiplierNeverDoublesOrHalvesAnySet() throws {
        let ctx = try makeContext()
        let barWeight = Exercise.defaultBarWeightKg
        let barbell = SetEntry(weight: 40, reps: 5, barWeightKg: barWeight,
                               loadMultiplier: 2,
                               loadAccountingMode: LoadAccountingMode.barbell.rawValue)
        let bodyweight = SetEntry(weight: 10, reps: 5, loadMultiplier: 2,
                                  loadAccountingMode: LoadAccountingMode.bodyweight.rawValue)
        ctx.insert(barbell); ctx.insert(bodyweight)
        #expect(abs(barbell.effectiveLoadKg - (40 + barWeight)) <= 0.01)
        #expect(bodyweight.effectiveLoadKg == 10)
    }

    @Test func effectiveLoadKgBodyweight() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 10, reps: 5, usesBodyweight: true,
                           loadAccountingMode: LoadAccountingMode.bodyweight.rawValue)
        ctx.insert(set)
        #expect(set.effectiveLoadKg == 10)
    }

    @Test func effectiveLoadKgBodyweightZero() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 0, reps: 10, usesBodyweight: true,
                           loadAccountingMode: LoadAccountingMode.bodyweight.rawValue)
        ctx.insert(set)
        #expect(set.effectiveLoadKg == 0)
    }

    // MARK: - prospectiveEffectiveLoadKg

    @Test func prospectiveEffectiveLoadKgBarbell() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Bench Press", equipment: .barbell)
        ctx.insert(ex)
        let bar = Exercise.defaultBarWeightKg
        #expect(abs(ex.prospectiveEffectiveLoadKg(rawWeightKg: 40) - (40 + bar)) <= 0.01)
    }

    @Test func prospectiveEffectiveLoadKgDumbbell() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Dumbbell Press", equipment: .dumbbell)
        ctx.insert(ex)
        #expect(ex.prospectiveEffectiveLoadKg(rawWeightKg: 30) == 30)
    }

    @Test func prospectiveEffectiveLoadKgCustomBarWeight() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "Bench Press", equipment: .barbell, defaultBarWeightKg: 15)
        ctx.insert(ex)
        #expect(abs(ex.prospectiveEffectiveLoadKg(rawWeightKg: 40) - 55) <= 0.01)
    }

    // MARK: - Seeding

    @Test func seedAddsLoadAccountingToExercise() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        let bench = try WorkoutRepository.allExercises(ctx).first { $0.name == "Bench Press" }
        #expect(bench?.loadAccountingModeValue == .barbell)
        if let b = bench {
            #expect(abs(b.defaultBarWeightKg - Exercise.defaultBarWeightKg) <= 0.01)
        } else {
            Issue.record("Bench Press not found")
        }
    }

    @Test func seedBodyweightNoBarWeight() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        let all = try WorkoutRepository.allExercises(ctx)
        // Find a bodyweight exercise from the starter library.
        if let bw = all.first(where: { $0.equipmentValue == .bodyweight && $0.loadAccountingMode != nil }) {
            #expect(bw.loadAccountingModeValue == .bodyweight)
            #expect(bw.defaultBarWeightKg == 0)
        }
        // At minimum, verify Pull-Up is present with correct accounting.
        if let pullUp = all.first(where: { $0.name == "Pull-Up" }) {
            #expect(pullUp.loadAccountingModeValue == .bodyweight,
                           "Pull-Up should have bodyweight accounting")
            #expect(pullUp.defaultBarWeightKg == 0)
        }
    }

    // MARK: - Snapshot on set creation

    @Test func addSetSnapshotsAccountingMetadata() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        guard let ex = try WorkoutRepository.allExercises(ctx).first(where: { $0.name == "Bench Press" }) else {
            Issue.record("Bench Press not found"); return
        }
        let session = WorkoutSession(title: "Test")
        ctx.insert(session)
        try ctx.save()

        let set = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 60, reps: 5, in: ctx)
        #expect(set.loadAccountingModeValue == .barbell)
        #expect(abs(set.barWeightKg - Exercise.defaultBarWeightKg) <= 0.01)
        #expect(set.weight == 60)
        #expect(set.effectiveLoadKg > set.weight)
    }

    @Test func addSetNeverDoubleCountsDumbbellOrKettlebellWeight() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        let session = WorkoutSession(title: "Bells")
        ctx.insert(session)
        try ctx.save()

        for name in ["Dumbbell Bench Press", "Kettlebell Clean"] {
            let exercise = try #require(try WorkoutRepository.allExercises(ctx).first { $0.name == name })
            let set = try WorkoutRepository.addSet(to: session, exercise: exercise,
                                                    weightKg: 20, reps: 8, in: ctx)
            #expect(set.weight == 20)
            #expect(set.effectiveLoadKg == 20,
                    "\(name) must use the entered total exactly once")
        }
    }

    @Test func addSetNoAccountingForMachine() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        guard let ex = try WorkoutRepository.allExercises(ctx).first(where: { $0.name == "Leg Press" }) else {
            Issue.record("Leg Press not found"); return
        }
        let session = WorkoutSession(title: "Test")
        ctx.insert(session)
        try ctx.save()

        let set = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 10, in: ctx)
        #expect(set.loadAccountingModeValue == nil)
        #expect(set.barWeightKg == 0)
        #expect(set.effectiveLoadKg == 100)
    }

    // MARK: - Export/Import round-trip

    @Test func exportIncludesLoadAccounting() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        guard let ex = try WorkoutRepository.allExercises(ctx).first(where: { $0.name == "Bench Press" }) else {
            Issue.record("Bench Press not found"); return
        }
        let session = WorkoutSession(title: "Test")
        ctx.insert(session)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 60, reps: 5, in: ctx)

        let export = try WorkoutRepository.buildExport(ctx)
        guard let es = export.sessions.first?.sets.first else {
            Issue.record("Expected one exported set"); return
        }
        #expect(es.loadAccountingMode == LoadAccountingMode.barbell.rawValue)
        #expect(es.barWeightKg != nil)
        #expect(es.loadMultiplier != nil)
    }

    @Test func mergeRestoresLoadAccounting() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        guard let ex = try WorkoutRepository.allExercises(ctx).first(where: { $0.name == "Bench Press" }) else {
            Issue.record("Bench Press not found"); return
        }
        let session = WorkoutSession(title: "Test")
        ctx.insert(session)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 60, reps: 5, in: ctx)

        let export = try WorkoutRepository.buildExport(ctx)
        let ctx2 = try makeContext()
        _ = try WorkoutRepository.merge(export, in: ctx2)
        let imported = try WorkoutRepository.allSessions(ctx2).first!
        let importedSet = imported.orderedSets.first!
        #expect(importedSet.loadAccountingModeValue == .barbell)
        #expect(abs(importedSet.barWeightKg - Exercise.defaultBarWeightKg) <= 0.01)
    }

    // MARK: - PR calculations use effective load

    @Test func pRCalculatorUsesEffectiveLoad() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        guard let ex = try WorkoutRepository.allExercises(ctx).first(where: { $0.name == "Bench Press" }) else {
            Issue.record("Bench Press not found"); return
        }
        let session = WorkoutSession(title: "Test")
        ctx.insert(session)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 40, reps: 5, in: ctx)

        let pr = WorkoutRepository.currentPR(for: ex, rule: .topWeight, formula: .epley)
        let expected = Exercise.defaultBarWeightKg + 40
        if let pr {
            #expect(abs(pr - expected) <= 0.1)
        } else {
            Issue.record("Expected a PR value")
        }
    }

    @Test func totalVolumeUsesEffectiveLoad() throws {
        let ctx = try makeContext()
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(ctx)
        guard let ex = try WorkoutRepository.allExercises(ctx).first(where: { $0.name == "Bench Press" }) else {
            Issue.record("Bench Press not found"); return
        }
        let session = WorkoutSession(title: "Test")
        ctx.insert(session)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 40, reps: 5, in: ctx)

        let effectiveWeight = Exercise.defaultBarWeightKg + 40
        let expectedVolume = effectiveWeight * 5
        #expect(abs(session.totalVolume - expectedVolume) <= 0.1)
    }

    // MARK: - Optional RPE

    @Test func setEntryRPEDefaultsToNil() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 60, reps: 8)
        ctx.insert(set)
        #expect(set.rpe == nil)
    }

    @Test func setEntryStoresRPE() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 60, reps: 8, rpe: 7.5)
        ctx.insert(set)
        #expect(set.rpe == 7.5)
    }

    @Test func setEntryRPEIsOptionalAfterEdit() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 60, reps: 8, rpe: 7)
        ctx.insert(set)
        try WorkoutRepository.updateSet(set, weightKg: 65, reps: 10, in: ctx)
        #expect(set.rpe == 7)
    }

    @Test func setEntryRPECanBeCleared() throws {
        let ctx = try makeContext()
        let set = SetEntry(weight: 60, reps: 8, rpe: 7)
        ctx.insert(set)
        try WorkoutRepository.updateSet(set, rpe: .some(nil), in: ctx)
        #expect(set.rpe == nil)
    }

    // MARK: - First-set / subsequent-set weight defaulting

    @Test func priorFirstWorkingSetWeightReturned() throws {
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
        #expect(firstWorking?.weight == 65)
    }

    @Test func noPriorSessionReturnsNoWeight() throws {
        let ctx = try makeContext()
        let ex = Exercise(name: "New Exercise")
        ctx.insert(ex)
        try ctx.save()
        let sets = WorkoutRepository.lastTimeSets(for: ex, excluding: nil)
        #expect(sets.isEmpty)
    }
}
#endif
