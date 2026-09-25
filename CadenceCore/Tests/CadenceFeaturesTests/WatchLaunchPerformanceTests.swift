import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

/// The Watch replays the phone's custom exercises on every launch. These pin
/// that an unchanged list is recognised and costs no writes.
final class WatchCustomExerciseStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
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

    func testFingerprintIgnoresOrder() {
        let a = row(1, "Cable Fly"), b = row(2, "Landmine Press")
        XCTAssertEqual(WatchSync.CustomExercise.fingerprint([a, b]),
                       WatchSync.CustomExercise.fingerprint([b, a]))
    }

    func testFingerprintChangesWithNameEditTimeOrMembership() {
        let base = WatchSync.CustomExercise.fingerprint([row(1, "Cable Fly")])
        XCTAssertNotEqual(base, WatchSync.CustomExercise.fingerprint([row(1, "Cable Flye")]))
        XCTAssertNotEqual(base, WatchSync.CustomExercise.fingerprint([row(1, "Cable Fly", at: 2)]))
        XCTAssertNotEqual(base, WatchSync.CustomExercise.fingerprint([row(1, "Cable Fly"), row(2, "Landmine Press")]))
        XCTAssertNotEqual(base, WatchSync.CustomExercise.fingerprint([]))
    }

    func testFingerprintIsStableAcrossCalls() {
        let rows = [row(1, "Cable Fly"), row(2, "Landmine Press")]
        XCTAssertEqual(WatchSync.CustomExercise.fingerprint(rows), WatchSync.CustomExercise.fingerprint(rows))
        XCTAssertTrue(WatchSync.CustomExercise.fingerprint(rows).hasPrefix("2-"))
    }

    func testApplyInsertsNewExercises() throws {
        let changed = try WatchCustomExerciseStore.apply([row(1, "Cable Fly"), row(2, "Landmine Press")], in: context)
        XCTAssertEqual(changed, 2)
        let stored = try WorkoutRepository.allExercises(context)
        XCTAssertEqual(Set(stored.map(\.name)), ["Cable Fly", "Landmine Press"])
        XCTAssertTrue(stored.allSatisfy(\.isCustom))
        XCTAssertEqual(stored.first { $0.name == "Cable Fly" }?.primaryMuscles, ["chest"])
    }

    func testReplayingTheSameListWritesNothing() throws {
        let rows = [row(1, "Cable Fly"), row(2, "Landmine Press")]
        try WatchCustomExerciseStore.apply(rows, in: context)
        XCTAssertEqual(try WatchCustomExerciseStore.apply(rows, in: context), 0)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try WorkoutRepository.allExercises(context).count, 2)
    }

    func testEditedExerciseUpdatesInPlace() throws {
        try WatchCustomExerciseStore.apply([row(1, "Cable Fly")], in: context)
        let changed = try WatchCustomExerciseStore.apply(
            [row(1, "Cable Fly", at: 5, muscles: ["chest", "deltoids"])], in: context)
        XCTAssertEqual(changed, 1)
        let stored = try WorkoutRepository.allExercises(context)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.primaryMuscles, ["chest", "deltoids"])
        XCTAssertEqual(stored.first?.updatedAt, Date(timeIntervalSince1970: 5))
    }

    func testMatchesAnExistingRowByNameIgnoringCase() throws {
        context.insert(Exercise(name: "cable fly", isCustom: true))
        try context.save()
        try WatchCustomExerciseStore.apply([row(1, "Cable Fly")], in: context)
        let stored = try WorkoutRepository.allExercises(context)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.name, "Cable Fly")
    }

    func testEmptyListIsANoOp() throws {
        XCTAssertEqual(try WatchCustomExerciseStore.apply([], in: context), 0)
        XCTAssertTrue(try WorkoutRepository.allExercises(context).isEmpty)
    }
}

/// The Watch's first-screen Heart Rate Access boundary follows HealthKit's
/// request status instead of a one-way UserDefaults flag.
final class WatchHealthAuthorizationGateTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "WatchHealthAuthorizationGateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    typealias Gate = WatchHealthAuthorizationGate

    func testFreshInstallShowsTheBoundaryFirst() {
        XCTAssertTrue(Gate.initialGateActive(defaults: defaults))
    }

    func testLegacyResolvedFlagNoLongerHidesAnUnansweredPrompt() {
        // The bug: an old build set this flag, and the boundary never came back.
        defaults.set(true, forKey: Gate.resolvedKey)
        XCTAssertFalse(Gate.initialGateActive(defaults: defaults))
        XCTAssertTrue(Gate.gateActive(current: false, status: .shouldRequest,
                                      dismissedThisLaunch: false, flowStarted: false))
    }

    func testLastKnownHealthKitAnswerDrivesTheFirstFrame() {
        defaults.set(true, forKey: Gate.resolvedKey)
        Gate.record(.shouldRequest, defaults: defaults)
        XCTAssertTrue(Gate.initialGateActive(defaults: defaults))
        Gate.record(.unnecessary, defaults: defaults)
        XCTAssertFalse(Gate.initialGateActive(defaults: defaults))
        Gate.record(.unknown, defaults: defaults)
        XCTAssertFalse(Gate.initialGateActive(defaults: defaults))
    }

    func testShouldRequestShowsUnlessSkippedThisLaunch() {
        XCTAssertTrue(Gate.gateActive(current: false, status: .shouldRequest,
                                      dismissedThisLaunch: false, flowStarted: false))
        XCTAssertFalse(Gate.gateActive(current: true, status: .shouldRequest,
                                       dismissedThisLaunch: true, flowStarted: false))
    }

    func testAnsweredPromptHidesTheBoundary() {
        XCTAssertFalse(Gate.gateActive(current: true, status: .unnecessary,
                                       dismissedThisLaunch: false, flowStarted: false))
    }

    func testAnsweredMidFlowKeepsTheScreenUntilContinue() {
        XCTAssertTrue(Gate.gateActive(current: true, status: .unnecessary,
                                      dismissedThisLaunch: false, flowStarted: true))
        XCTAssertFalse(Gate.gateActive(current: false, status: .unnecessary,
                                       dismissedThisLaunch: false, flowStarted: true))
    }

    func testUnknownStatusKeepsWhateverIsShowing() {
        XCTAssertTrue(Gate.gateActive(current: true, status: .unknown,
                                      dismissedThisLaunch: false, flowStarted: false))
        XCTAssertFalse(Gate.gateActive(current: false, status: .unknown,
                                       dismissedThisLaunch: false, flowStarted: false))
    }
}
