import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

final class WatchSingleExerciseSuggestionContextStoreTests {
    private var suite = ""
    private var defaults: UserDefaults!

    init() {
        suite = "suggestion-store-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    deinit {
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

    @Test func roundTripAndPersistsAcrossReload() throws {
        #expect(WatchSingleExerciseSuggestionContextStore(defaults: defaults).replaceIfNewer(make(at: 100)))
        let reloaded = WatchSingleExerciseSuggestionContextStore(defaults: UserDefaults(suiteName: suite)!)
        #expect(reloaded.load() == make(at: 100))
    }

    @Test func olderEqualAndFutureCannotReplace() {
        let store = WatchSingleExerciseSuggestionContextStore(defaults: defaults)
        #expect(store.replaceIfNewer(make(at: 200)))
        #expect(!store.replaceIfNewer(make(at: 100, sets: 4)))
        #expect(!store.replaceIfNewer(make(at: 200, sets: 4)))
        #expect(store.replace(make(at: 900, version: 99)) == .keptExisting)
        #expect(store.load() == make(at: 200))
        #expect(store.replaceIfNewer(make(at: 300)))
    }

    @Test func corruptPayloadAfterValidKeepsRetainedContext() throws {
        let store = WatchSingleExerciseSuggestionContextStore(defaults: defaults)
        store.replaceIfNewer(make(at: 100))
        let key = WatchSync.Key.singleExerciseSuggestionContext
        let incoming = WatchSync.IncomingContext.from(
            context: [key: Data("not json".utf8)],
            applyingTo: WatchSync.Preferences(unit: .kilograms, intervalColorBlind: false, restSeconds: 90,
                                              warmupMinutes: 5, cooldownMinutes: 5, workoutSounds: true,
                                              spokenCues: true, recentPartnerNames: []))
        #expect(incoming.singleExerciseSuggestionContext == nil)
        let future = try #require(make(at: 500, version: 2).propertyListValue)
        #expect(WatchSingleExerciseSuggestionContext.decodePayload(future) == nil)
        #expect(store.load() == make(at: 100))
    }

    @Test func corruptStoredDataIsDiscarded() {
        defaults.set(Data("junk".utf8), forKey: WatchSingleExerciseSuggestionContextStore.defaultsKey)
        let store = WatchSingleExerciseSuggestionContextStore(defaults: defaults)
        #expect(store.load() == nil)
        #expect(store.replaceIfNewer(make(at: 1)))
    }

    @Test func contextParsingAndFingerprintChangesOnlyWithSnapshot() throws {
        let key = WatchSync.Key.singleExerciseSuggestionContext
        let a = try #require(make(at: 100).propertyListValue)
        let b = try #require(make(at: 200).propertyListValue)
        let parsed = WatchSync.IncomingContext.from(
            context: [key: a],
            applyingTo: WatchSync.Preferences(unit: .kilograms, intervalColorBlind: false, restSeconds: 90,
                                              warmupMinutes: 5, cooldownMinutes: 5, workoutSounds: true,
                                              spokenCues: true, recentPartnerNames: []))
        #expect(parsed.singleExerciseSuggestionContext == make(at: 100))
        let none = WatchSyncHandshake.Components(context: [:])
        let withA = WatchSyncHandshake.Components(context: [key: a])
        let withB = WatchSyncHandshake.Components(context: [key: b])
        #expect(none != withA)
        #expect(withA != withB)
        #expect(withA == WatchSyncHandshake.Components(context: [key: a]))
    }
}
