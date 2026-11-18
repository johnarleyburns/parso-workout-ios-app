import Foundation
import Testing
@testable import CadenceFeatures

struct PlatformSnapshotTests {
    @Test func snapshotRoundTripsThroughSharedStore() {
        let suite = "cadence.platform.snapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let snapshot = CadenceTodaySnapshot(
            dayKey: "2026-09-11", planTitle: "Coach plan",
            sessionTitles: ["Upper strength", "Easy walk"],
            readinessLabel: "Recovery looks good",
            updatedAt: Date(timeIntervalSince1970: 123))
        CadencePlatformSnapshotStore.save(snapshot, defaults: defaults)

        #expect(CadencePlatformSnapshotStore.load(defaults: defaults) == snapshot)
    }

    @Test func watchWidgetStateRoundTripsAndClears() {
        let suite = "cadence.platform.watch-widget.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = CadenceWatchWidgetState(
            workoutTitle: "Upper strength",
            restEndsAt: Date(timeIntervalSince1970: 456))
        CadenceWatchWidgetStore.save(state, defaults: defaults)

        #expect(CadenceWatchWidgetStore.load(defaults: defaults) == state)
        CadenceWatchWidgetStore.clear(defaults: defaults)
        #expect(CadenceWatchWidgetStore.load(defaults: defaults) == nil)
    }

    @Test func complicationStateIsActiveWhileWorkoutRunsAndIdleOtherwise() {
        let suite = "cadence.platform.complication.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 100_000)

        #expect(CadenceWatchComplicationState.current(defaults: defaults, now: now) == .idle)

        let start = now.addingTimeInterval(-600)
        CadenceWatchComplicationState.setActive(
            CadenceWatchActiveWorkout(workoutType: "cardio", startedAt: start), defaults: defaults)
        #expect(CadenceWatchComplicationState.current(defaults: defaults, now: now) ==
                       .active(workoutType: "cardio", startedAt: start))

        // A stale marker (crash before clear) is ignored.
        #expect(CadenceWatchComplicationState.current(
            defaults: defaults, now: now.addingTimeInterval(CadenceWatchComplicationState.maxAge)) == .idle)

        CadenceWatchComplicationState.setActive(nil, defaults: defaults)
        #expect(CadenceWatchComplicationState.current(defaults: defaults, now: now) == .idle)
    }


    @Test func liveActivityActionIsConsumedOnce() {
        let defaults = UserDefaults(suiteName: "PlatformSnapshotTests.liveActivity.\(UUID().uuidString)")!
        CadencePlatformRequestStore.requestLiveActivity(.logPlannedSet, token: "owner-2", defaults: defaults)
        #expect(CadencePlatformRequestStore.consumeLiveActivityRequest(defaults: defaults) ==
                       .init(action: .logPlannedSet, token: "owner-2"))
        #expect(CadencePlatformRequestStore.consumeLiveActivity(defaults: defaults) == nil)
    }

    @Test func latestLiveActivityActionReplacesStaleAction() {
        let defaults = UserDefaults(suiteName: "PlatformSnapshotTests.liveActivity.replace.\(UUID().uuidString)")!
        CadencePlatformRequestStore.requestLiveActivity(.addRest, defaults: defaults)
        CadencePlatformRequestStore.requestLiveActivity(.skipRest, defaults: defaults)
        #expect(CadencePlatformRequestStore.consumeLiveActivityRequest(defaults: defaults)?.action == .skipRest)
    }

    @Test func legacyLiveActivityStringIsDiscarded() {
        let defaults = UserDefaults(suiteName: "PlatformSnapshotTests.liveActivity.legacy.\(UUID().uuidString)")!
        defaults.set(CadencePlatformRequestStore.LiveActivityAction.addRest.rawValue,
                     forKey: "cadence.platform.liveActivity.action")
        #expect(CadencePlatformRequestStore.consumeLiveActivityRequest(defaults: defaults) == nil)
    }

    @Test func legacySnapshotAndDeepLinkWireValuesStayCompatible() throws {
        let legacy = Data(#"{"dayKey":"2026-09-11","planTitle":"Upper","sessionTitles":["Strength"],"updatedAt":0}"#.utf8)
        let snapshot = try JSONDecoder().decode(CadenceTodaySnapshot.self, from: legacy)
        #expect(snapshot.weeklyMuscles == [])
        #expect(snapshot.setsCompleted == nil)
        #expect(snapshot.updatedAt == Date(timeIntervalSinceReferenceDate: 0))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        #expect(encoded["planTitle"] as? String == "Upper")
        #expect(Set(ThisWeekDestination.allCases.map(\.rawValue)) == ["muscleCoverage", "strength", "cardio"])
        #expect(Format.duration(3661) == "1:01:01")
        #expect(Format.distance(1500) == "1.50 km")
    }

}
