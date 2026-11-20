#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// The Watch replays the phone's custom exercises on every launch. These pin
/// that an unchanged list is recognised and costs no writes.
final class WatchCustomExerciseStoreTests {
    private nonisolated(unsafe) var container: ModelContainer!
    private nonisolated(unsafe) var context: ModelContext!

    init() throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
    }

    deinit {
        context = nil
        container = nil
    }

    private func row(_ id: Int, _ name: String, at seconds: Double = 1,
                     muscles: [String] = ["chest"]) -> WatchSync.CustomExercise {
        WatchSync.CustomExercise(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", id))!,
            name: name, category: "push", equipment: "cable",
            primaryMuscles: muscles, searchKeywords: [name.lowercased()],
            updatedAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func fingerprintIgnoresOrder() {
        let a = row(1, "Cable Fly"), b = row(2, "Landmine Press")
        #expect(WatchSync.CustomExercise.fingerprint([a, b]) ==
                       WatchSync.CustomExercise.fingerprint([b, a]))
    }

    @Test func fingerprintChangesWithNameEditTimeOrMembership() {
        let base = WatchSync.CustomExercise.fingerprint([row(1, "Cable Fly")])
        #expect(base != WatchSync.CustomExercise.fingerprint([row(1, "Cable Flye")]))
        #expect(base != WatchSync.CustomExercise.fingerprint([row(1, "Cable Fly", at: 2)]))
        #expect(base != WatchSync.CustomExercise.fingerprint([row(1, "Cable Fly"), row(2, "Landmine Press")]))
        #expect(base != WatchSync.CustomExercise.fingerprint([]))
    }

    @Test func fingerprintIsStableAcrossCalls() {
        let rows = [row(1, "Cable Fly"), row(2, "Landmine Press")]
        #expect(WatchSync.CustomExercise.fingerprint(rows) == WatchSync.CustomExercise.fingerprint(rows))
        #expect(WatchSync.CustomExercise.fingerprint(rows).hasPrefix("2-"))
    }

    @Test func applyInsertsNewExercises() throws {
        let changed = try WatchCustomExerciseStore.apply([row(1, "Cable Fly"), row(2, "Landmine Press")], in: context)
        #expect(changed == 2)
        let stored = try WorkoutRepository.allExercises(context)
        #expect(Set(stored.map(\.name)) == ["Cable Fly", "Landmine Press"])
        #expect(stored.allSatisfy { $0.isCustom })
        #expect(stored.first { $0.name == "Cable Fly" }?.primaryMuscles == ["chest"])
    }

    @Test func replayingTheSameListWritesNothing() throws {
        let rows = [row(1, "Cable Fly"), row(2, "Landmine Press")]
        try WatchCustomExerciseStore.apply(rows, in: context)
        #expect(try WatchCustomExerciseStore.apply(rows, in: context) == 0)
        #expect(!context.hasChanges)
        #expect(try WorkoutRepository.allExercises(context).count == 2)
    }

    @Test func editedExerciseUpdatesInPlace() throws {
        try WatchCustomExerciseStore.apply([row(1, "Cable Fly")], in: context)
        let changed = try WatchCustomExerciseStore.apply(
            [row(1, "Cable Fly", at: 5, muscles: ["chest", "deltoids"])], in: context)
        #expect(changed == 1)
        let stored = try WorkoutRepository.allExercises(context)
        #expect(stored.count == 1)
        #expect(stored.first?.primaryMuscles == ["chest", "deltoids"])
        #expect(stored.first?.updatedAt == Date(timeIntervalSince1970: 5))
    }

    @Test func matchesAnExistingRowByNameIgnoringCase() throws {
        context.insert(Exercise(name: "cable fly", isCustom: true))
        try context.save()
        try WatchCustomExerciseStore.apply([row(1, "Cable Fly")], in: context)
        let stored = try WorkoutRepository.allExercises(context)
        #expect(stored.count == 1)
        #expect(stored.first?.name == "Cable Fly")
    }

    @Test func emptyListIsANoOp() throws {
        #expect(try WatchCustomExerciseStore.apply([], in: context) == 0)
        #expect(try WorkoutRepository.allExercises(context).isEmpty)
    }
}

/// The Watch's first-screen Heart Rate Access boundary follows HealthKit's
/// request status instead of a one-way UserDefaults flag.
final class WatchHealthAuthorizationGateTests {
    private let defaults = InMemoryDefaultsStore()

    typealias Gate = WatchHealthAuthorizationGate

    @Test func freshInstallShowsTheBoundaryFirst() {
        #expect(Gate.initialGateActive(defaults: defaults))
    }

    @Test func legacyResolvedFlagNoLongerHidesAnUnansweredPrompt() {
        // The bug: an old build set this flag, and the boundary never came back.
        defaults.set(true, forKey: Gate.resolvedKey)
        #expect(!Gate.initialGateActive(defaults: defaults))
        #expect(Gate.gateActive(current: false, status: .shouldRequest,
                                      dismissedThisLaunch: false, flowStarted: false))
    }

    @Test func lastKnownHealthKitAnswerDrivesTheFirstFrame() {
        defaults.set(true, forKey: Gate.resolvedKey)
        Gate.record(.shouldRequest, defaults: defaults)
        #expect(Gate.initialGateActive(defaults: defaults))
        Gate.record(.unnecessary, defaults: defaults)
        #expect(!Gate.initialGateActive(defaults: defaults))
        Gate.record(.unknown, defaults: defaults)
        #expect(!Gate.initialGateActive(defaults: defaults))
    }

    @Test func shouldRequestShowsUnlessSkippedThisLaunch() {
        #expect(Gate.gateActive(current: false, status: .shouldRequest,
                                      dismissedThisLaunch: false, flowStarted: false))
        #expect(!Gate.gateActive(current: true, status: .shouldRequest,
                                       dismissedThisLaunch: true, flowStarted: false))
    }

    @Test func answeredPromptHidesTheBoundary() {
        #expect(!Gate.gateActive(current: true, status: .unnecessary,
                                       dismissedThisLaunch: false, flowStarted: false))
    }

    @Test func answeredMidFlowKeepsTheScreenUntilContinue() {
        #expect(Gate.gateActive(current: true, status: .unnecessary,
                                      dismissedThisLaunch: false, flowStarted: true))
        #expect(!Gate.gateActive(current: false, status: .unnecessary,
                                       dismissedThisLaunch: false, flowStarted: true))
    }

    @Test func unknownStatusKeepsWhateverIsShowing() {
        #expect(Gate.gateActive(current: true, status: .unknown,
                                      dismissedThisLaunch: false, flowStarted: false))
        #expect(!Gate.gateActive(current: false, status: .unknown,
                                       dismissedThisLaunch: false, flowStarted: false))
    }
}
#endif
