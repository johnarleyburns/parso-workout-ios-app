#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct ExerciseRepeatDefaultsTests {
    private let lastKg = WorkoutMath.canonical(205, from: .pounds)
    private let olderKg = WorkoutMath.canonical(250, from: .pounds)

    private func history(in context: ModelContext) throws -> Exercise {
        let exercise = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", in: context)
        let prior = try WorkoutRepository.createSession(title: "Previous", in: context)
        prior.date = Date(timeIntervalSince1970: 100)
        _ = try WorkoutRepository.addSet(to: prior, exercise: exercise, weightKg: olderKg, reps: 6, in: context)
        _ = try WorkoutRepository.addSet(to: prior, exercise: exercise, weightKg: lastKg, reps: 8, in: context)
        prior.endedAt = Date(timeIntervalSince1970: 200)
        try context.save()
        return exercise
    }

    @Test func watchLocalHistoryRepeats205For8InsteadOf250For6() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        let exercise = try history(in: context)
        let model = WatchStrengthFlowModel(context: context, unit: .pounds, cooldownDefault: 0, restDefault: 60)
        model.start(createSession: true)
        _ = model.addExercise(named: exercise.name)
        model.startLogSet(for: exercise)
        #expect(abs(model.currentWeightDisplay - 205) <= 0.0001)
        #expect(model.currentReps == 8)
    }

    private struct SyncedHistory: WatchSetDefaultHistoryProviding {
        let snapshot: WatchSetDefaultSnapshot
        func history(exerciseKey: String, performerID: String, performerName: String?) -> PerformerSetPlanner.History {
            snapshot.history(exerciseKey: exerciseKey, performerID: performerID, performerName: performerName)
        }
    }

    @Test func watchSyncedHistoryRepeats205For8WithoutPhoneReachability() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        let snapshot = WatchSetDefaultSnapshot(generatedAt: Date(), performers: [
            .init(id: "owner", displayName: "Me", exercises: [
                .init(id: "Back Squat", displayName: "Back Squat", repLadders: [[6, 8]],
                    samples: [.init(weightKg: olderKg, reps: 6), .init(weightKg: lastKg, reps: 8)], firstWorkingWeightKg: olderKg)
            ], generalRepLadders: [])
        ])
        let model = WatchStrengthFlowModel(context: context, unit: .pounds,
            setDefaultHistory: SyncedHistory(snapshot: snapshot))
        model.start(createSession: true)
        _ = model.addExercise(named: "Back Squat")
        let exercise = try #require(model.exerciseList.first?.exercise)
        model.startLogSet(for: exercise)
        #expect(abs(model.currentWeightDisplay - 205) <= 0.0001)
        #expect(model.currentReps == 8)
    }

    @Test func newerWatchHistoryBeatsAnOlderSyncedSetEvenInANewSnapshot() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        let exercise = try history(in: context)
        let snapshot = WatchSetDefaultSnapshot(generatedAt: Date(), performers: [
            .init(id: "owner", displayName: "Me", exercises: [
                .init(id: "Back Squat", displayName: "Back Squat", repLadders: [[6]],
                    samples: [.init(weightKg: olderKg, reps: 6, completedAt: .distantPast)], firstWorkingWeightKg: olderKg)
            ], generalRepLadders: [])
        ])
        let model = WatchStrengthFlowModel(context: context, unit: .pounds,
            setDefaultHistory: SyncedHistory(snapshot: snapshot))
        model.start(createSession: true)
        _ = model.addExercise(named: exercise.name)
        model.startLogSet(for: exercise)
        #expect(abs(model.currentWeightDisplay - 205) <= 0.0001)
        #expect(model.currentReps == 8)
    }

    @Test func phoneRenderHistoryAlreadyRepeatsTheExactLastWorkingSet() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        let exercise = try history(in: context)
        let current = try WorkoutRepository.createSession(title: "Current", in: context)
        // Link the exercise without introducing a working-set override today.
        _ = try WorkoutRepository.addSet(to: current, exercise: exercise, weightKg: 20, reps: 3,
                                         isWarmup: true, in: context)
        let state = SessionRenderModel.build(session: current, prRule: .topWeight, formula: .epley, allPeople: [])
        let resolved = PerformerSetPlanner.resolve(setIndex: 0, performerPlan: nil, ownerPlan: [],
            ownerLadder: nil, isOwner: true,
            history: state.performerHistory(forExerciseID: exercise.id, performerID: nil))
        #expect(abs((resolved.weightKg ?? 0) - lastKg) <= 0.0001)
        #expect(resolved.reps == 8)
    }
}
#endif
