import XCTest
@testable import CadenceFeatures
import CadenceCore

final class WatchSingleExerciseSuggestionContextStoreTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "suggestion-store-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func make(at seconds: TimeInterval, sets: Int = 3, version: Int = 1) -> WatchSingleExerciseSuggestionContext {
        let when = Date(timeIntervalSince1970: seconds)
        let schedule = WatchSingleExerciseSuggestionContext.Schedule(CoachSchedulePreferences(
            restPreference: .fixed(days: [.sunday])))
        return WatchSingleExerciseSuggestionContext(
            version: version, generatedAt: when,
            baseInput: .init(
                completedSetsByMuscle: ["chest": 2],
                candidates: [.init(id: "legacy:bench", name: "Bench", mechanicsRawValue: "compound",
                                   primaryMuscles: ["chest"])],
                trackedGroupIDs: ["chest"], preferredSetsPerExercise: sets,
                trainingGoalRawValue: TrainingGoal.hypertrophy.rawValue,
                preferredStyleRawValue: SuggestedWorkoutStyle.fitness.rawValue,
                engineContext: .init(experienceRawValue: ExperienceLevel.intermediate.rawValue,
                                     schedule: schedule, availableEquipmentRawValues: [],
                                     environment: "commercial_gym", asOf: when)))
    }

    func testRoundTripAndPersistsAcrossReload() throws {
        XCTAssertTrue(WatchSingleExerciseSuggestionContextStore(defaults: defaults).replaceIfNewer(make(at: 100)))
        let reloaded = WatchSingleExerciseSuggestionContextStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.load(), make(at: 100))
    }

    func testOlderEqualAndFutureCannotReplace() {
        let store = WatchSingleExerciseSuggestionContextStore(defaults: defaults)
        XCTAssertTrue(store.replaceIfNewer(make(at: 200)))
        XCTAssertFalse(store.replaceIfNewer(make(at: 100, sets: 4)))
        XCTAssertFalse(store.replaceIfNewer(make(at: 200, sets: 4)))
        XCTAssertEqual(store.replace(make(at: 900, version: 99)), .keptExisting)
        XCTAssertEqual(store.load(), make(at: 200))
        XCTAssertTrue(store.replaceIfNewer(make(at: 300)))
    }

    func testCorruptPayloadAfterValidKeepsRetainedContext() throws {
        let store = WatchSingleExerciseSuggestionContextStore(defaults: defaults)
        store.replaceIfNewer(make(at: 100))
        let key = WatchSync.Key.singleExerciseSuggestionContext
        let incoming = WatchSync.IncomingContext.from(
            context: [key: Data("not json".utf8)],
            applyingTo: WatchSync.Preferences(unit: .kilograms, intervalColorBlind: false, restSeconds: 90,
                                              warmupMinutes: 5, cooldownMinutes: 5, workoutSounds: true,
                                              spokenCues: true, recentPartnerNames: []))
        XCTAssertNil(incoming.singleExerciseSuggestionContext)
        let future = try XCTUnwrap(make(at: 500, version: 2).propertyListValue)
        XCTAssertNil(WatchSingleExerciseSuggestionContext.decodePayload(future))
        XCTAssertEqual(store.load(), make(at: 100))
    }

    func testCorruptStoredDataIsDiscarded() {
        defaults.set(Data("junk".utf8), forKey: WatchSingleExerciseSuggestionContextStore.defaultsKey)
        let store = WatchSingleExerciseSuggestionContextStore(defaults: defaults)
        XCTAssertNil(store.load())
        XCTAssertTrue(store.replaceIfNewer(make(at: 1)))
    }

    func testContextParsingAndFingerprintChangesOnlyWithSnapshot() throws {
        let key = WatchSync.Key.singleExerciseSuggestionContext
        let a = try XCTUnwrap(make(at: 100).propertyListValue)
        let b = try XCTUnwrap(make(at: 200).propertyListValue)
        let parsed = WatchSync.IncomingContext.from(
            context: [key: a],
            applyingTo: WatchSync.Preferences(unit: .kilograms, intervalColorBlind: false, restSeconds: 90,
                                              warmupMinutes: 5, cooldownMinutes: 5, workoutSounds: true,
                                              spokenCues: true, recentPartnerNames: []))
        XCTAssertEqual(parsed.singleExerciseSuggestionContext, make(at: 100))
        let none = WatchSyncHandshake.Components(context: [:])
        let withA = WatchSyncHandshake.Components(context: [key: a])
        let withB = WatchSyncHandshake.Components(context: [key: b])
        XCTAssertNotEqual(none, withA)
        XCTAssertNotEqual(withA, withB)
        XCTAssertEqual(withA, WatchSyncHandshake.Components(context: [key: a]))
    }
}
